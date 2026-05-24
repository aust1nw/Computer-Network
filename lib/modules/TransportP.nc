#include "../../includes/packet.h"
#include "../../includes/socket.h"
#include "../../includes/transport_header.h"
#include "../../includes/ip_header.h"

#define NULL_SOCKET 0xFF
#define LISTENER_UNLINKED 0xFF
#define TIME_WAIT_PERIOD 2000
#define RTO 100
#define TRANSPORT_HEADER_SIZE TCP_PACKET_HEADER_LENGTH
#define MAX_DATA_SIZE (PACKET_MAX_PAYLOAD_SIZE - TRANSPORT_HEADER_SIZE - IP_HEADER_LENGTH)
#define RETRANSMIT_QUEUE_SIZE 32
#define RTT_ALPHA_NUM 4
#define RTT_ALPHA_DEN 10
#define RTT_MIN 2
#define RTT_MAX 2000

generic module TransportP(){
    provides interface Transport;
    
    uses interface Packet;
    uses interface SimpleSend as Send;
    uses interface Timer<TMilli> as TCPTimer;
    uses interface Random;
    uses interface IPForwarding;
}

implementation {
    socket_store_t sockets[MAX_NUM_OF_SOCKETS];

    uint8_t advertisedWindow[MAX_NUM_OF_SOCKETS];
    
    // Retransmission queue for each socket
    uint8_t retransmitSeq[MAX_NUM_OF_SOCKETS][RETRANSMIT_QUEUE_SIZE];
    uint32_t retransmitTime[MAX_NUM_OF_SOCKETS][RETRANSMIT_QUEUE_SIZE];
    uint16_t retransmitLen[MAX_NUM_OF_SOCKETS][RETRANSMIT_QUEUE_SIZE];
    uint8_t retransmitHead[MAX_NUM_OF_SOCKETS];
    uint8_t retransmitTail[MAX_NUM_OF_SOCKETS];

    bool timerRunning = FALSE;

    static bool seq_eq(uint8_t a, uint8_t b)  { return a == b; }
    static bool seq_lt(uint8_t a, uint8_t b)  { return (int8_t)(a - b) < 0; }
    static bool seq_le(uint8_t a, uint8_t b)  { return (int8_t)(a - b) <= 0; }
    static bool seq_in_window(uint8_t x, uint8_t start, uint8_t win) {
        // true iff x in [start, start+win) modulo 256
        return (uint8_t)(x - start) < win;
    }

    static bool tuple_bound(socket_t fd) {
    return sockets[fd].src != 0 &&
           sockets[fd].dest.port != 0 &&
           sockets[fd].dest.addr != 0 &&
           sockets[fd].local_addr == TOS_NODE_ID;
    }
    
    static bool state_allows_data(socket_t fd) {
        switch (sockets[fd].state) {
            case ESTABLISHED:
            case CLOSE_WAIT:
            case FIN_WAIT_1:
            case FIN_WAIT_2:
            case LAST_ACK:
                return TRUE;
            default:
                return FALSE;
        }
    }

    static bool state_allows_ack(socket_t fd) {
        // ACKs are fine once we’re in handshake or beyond, but NOT in CLOSED/LISTEN
        switch (sockets[fd].state) {
            case SYN_SENT:
            case SYN_RCVD:
            case ESTABLISHED:
            case CLOSE_WAIT:
            case FIN_WAIT_1:
            case FIN_WAIT_2:
            case LAST_ACK:
            case TIME_WAIT:
                return TRUE;
            default:
                return FALSE;
        }
    }

    // Finds an unused socket
    socket_t find_free_socket(){
        uint8_t i;
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++){
            if(sockets[i].state == CLOSED){
                memset(&sockets[i], 0, sizeof(socket_store_t));
                sockets[i].state = CLOSED;
                sockets[i].flag = LISTENER_UNLINKED;
                sockets[i].lastWritten = 0;
                sockets[i].lastAck = 0;
                sockets[i].lastSent = 0;
                sockets[i].lastRead = 0;
                sockets[i].lastRcvd = 0;
                sockets[i].nextExpected = 0;
                sockets[i].effectiveWindow = SOCKET_BUFFER_SIZE;
                sockets[i].RTT = 150;
                
                advertisedWindow[i] = SOCKET_BUFFER_SIZE;

                retransmitHead[i] = 0;
                retransmitTail[i] = 0;
                return i;
            }
        }
        return NULL_SOCKET;
    }
    
    // Finds socket by 4-tuple
    socket_t find_socket_by_addr(socket_port_t local_port, uint16_t local_addr, socket_port_t remote_port, uint16_t remote_addr){
        uint8_t i;
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++){
            if(sockets[i].state != CLOSED && sockets[i].src == local_port && sockets[i].local_addr == local_addr && sockets[i].dest.port == remote_port && sockets[i].dest.addr == remote_addr){
                dbg(TRANSPORT_CHANNEL, "Node %u: Found socket %u: local=%u:%u, remote=%u:%u\n", TOS_NODE_ID, i, local_addr, local_port, remote_addr, remote_port);
                return i;
            }
        }
        dbg(TRANSPORT_CHANNEL, "Node %u: No socket found for local=%u:%u, remote=%u:%u\n",TOS_NODE_ID, local_addr, local_port, remote_addr, remote_port);
        return NULL_SOCKET;
    }

    // Finds listening socket
    socket_t find_listener_socket(socket_port_t local_port, uint16_t local_addr){
        uint8_t i;
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++){
            if(sockets[i].state == LISTEN && sockets[i].src == local_port && sockets[i].local_addr == local_addr){
                return i;
            }
        }
        return NULL_SOCKET;
    }

    
    // Check if sequence is acknowledged (handles wrap-around)
    bool is_sequence_acknowledged(socket_t fd, uint8_t seq_num) {
        uint8_t last_ack = sockets[fd].lastAck;
        uint8_t last_sent = sockets[fd].lastSent;
        
        if(last_sent == last_ack) {
            return seq_num < last_ack;
        } 

        if(last_ack > last_sent){
            return (seq_num < last_ack) || (seq_num >= last_sent);
        }
        else {
            return seq_num < last_ack;
        }
    }
    
    // Add packet to retransmission queue
    error_t add_to_retransmit_queue(socket_t fd, uint8_t seq_num, uint16_t data_len) {
        uint8_t next_tail;
        uint8_t i;

        if(fd == NULL_SOCKET) return FAIL;
        
        i = retransmitHead[fd];
        while(i != retransmitTail[fd]) {
            if(retransmitSeq[fd][i] == seq_num) {
                return SUCCESS;  // Already queued
            }
            i = (i + 1) % RETRANSMIT_QUEUE_SIZE;
        }

        next_tail = (retransmitTail[fd] + 1) % RETRANSMIT_QUEUE_SIZE;

        if(next_tail == retransmitHead[fd]) {
            dbg(TRANSPORT_CHANNEL, "Node %u: Retransmit queue full for socket %u\n", TOS_NODE_ID, fd);
            return FAIL;
        }
        
        retransmitSeq[fd][retransmitTail[fd]] = seq_num;
        retransmitLen[fd][retransmitTail[fd]] = data_len;
        retransmitTime[fd][retransmitTail[fd]] = call TCPTimer.getNow();
        retransmitTail[fd] = next_tail;
        
        // Start timer if this is the first packet in queue
        if((retransmitHead[fd] + 1) % RETRANSMIT_QUEUE_SIZE == retransmitTail[fd]) {
            uint32_t rto = sockets[fd].RTT * 2;
            if(rto < 50)  rto = 50;    // min 50 ms
            if(rto > 5000) rto = 5000; // max 5 sec
            call TCPTimer.startOneShot(rto);
        }
        
        return SUCCESS;
    }
    
    // Remove acknowledged packets from queue
    void remove_acked_packets(socket_t fd, uint8_t ack_num) {
        if(fd == NULL_SOCKET) return;

        sockets[fd].lastAck = ack_num;
        
        while(retransmitHead[fd] != retransmitTail[fd]) {
            uint8_t seq_in_queue = retransmitSeq[fd][retransmitHead[fd]];
            
            if(is_sequence_acknowledged(fd, seq_in_queue)) {
                uint32_t now = call TCPTimer.getNow();
                uint32_t sample_rtt = now - retransmitTime[fd][retransmitHead[fd]];
                if(sample_rtt >= RTT_MIN && sample_rtt <= RTT_MAX){
                    uint32_t old = sockets[fd].RTT;
                    uint32_t newr = (RTT_ALPHA_NUM * sample_rtt + (RTT_ALPHA_DEN - RTT_ALPHA_NUM) * old) / RTT_ALPHA_DEN;
                    sockets[fd].RTT = newr;
                    dbg(TRANSPORT_CHANNEL, "Node %u: Updated RTT sample=%u EWMA=%u socket %u\n", TOS_NODE_ID, sample_rtt, newr, fd);
                }
                
                retransmitHead[fd] = (retransmitHead[fd] + 1) % RETRANSMIT_QUEUE_SIZE;
            } 
            else {
                break;
            }
        }
    }
    
    // Send data packet
    error_t send_data_packet(socket_t fd, uint8_t *data, uint16_t data_len, uint8_t flags, uint8_t seq, uint8_t ack) {
        transport_header tcp_hdr;
        uint8_t payload[PACKET_MAX_PAYLOAD_SIZE];
        uint16_t total_len = TRANSPORT_HEADER_SIZE + data_len;

        if(fd == NULL_SOCKET || fd >= MAX_NUM_OF_SOCKETS) return FAIL;
        if(total_len > PACKET_MAX_PAYLOAD_SIZE) return FAIL;

        if((flags & SYN_FLAG) == 0 && !tuple_bound(fd)) {
            dbg(TRANSPORT_CHANNEL, "Node %u: Socket %u tuple not bound\n", TOS_NODE_ID, fd);
            return FAIL;
        }

        if(data_len > 0 && !state_allows_data(fd)){
            dbg(TRANSPORT_CHANNEL, "Node %u: Drop DATA: bad state fd=%u state=%u\n",
                TOS_NODE_ID, fd, sockets[fd].state);
            return FAIL;
        }

        memset(&tcp_hdr, 0, sizeof(transport_header));

        // Fill transport header
        tcp_hdr.src_port = sockets[fd].src;
        tcp_hdr.dest_port = sockets[fd].dest.port;
        tcp_hdr.seq_num = (uint8_t)seq;
        tcp_hdr.ack_num = (uint8_t)ack;
        tcp_hdr.flags = flags;
        tcp_hdr.window = advertisedWindow[fd];
        tcp_hdr.len = (uint8_t)data_len;

        // Copy header and data
        memcpy(payload, (uint8_t*)&tcp_hdr, TRANSPORT_HEADER_SIZE);
        if(data != NULL && data_len > 0){
            memcpy(payload + TRANSPORT_HEADER_SIZE, data, data_len);
        }

        dbg(TRANSPORT_CHANNEL, "Node %u: SENDING TCP: src_port=%u dest_port=%u flags=0x%x seq=%u ack=%u\n", TOS_NODE_ID, tcp_hdr.src_port, tcp_hdr.dest_port, tcp_hdr.flags, tcp_hdr.seq_num, tcp_hdr.ack_num);

        if(data_len > 0 && sockets[fd].state == ESTABLISHED && (flags & (SYN_FLAG | FIN_FLAG | RST_FLAG)) == 0) {
            if (add_to_retransmit_queue(fd, seq, data_len) == FAIL) {
                dbg(TRANSPORT_CHANNEL, "Node %u: Queue full! Cannot send seq %u\n", TOS_NODE_ID, seq);
                return FAIL; // ABORT SENDING if we can't track it
            }
        }
        // Send via IPForwarding
        if(call IPForwarding.sendTCP(sockets[fd].dest.addr, payload, total_len) == SUCCESS){
            dbg(TRANSPORT_CHANNEL, "Node %u: Sent packet flags=0x%x seq=%u len=%u to %u\n", TOS_NODE_ID, flags, seq, data_len, sockets[fd].dest.addr);
            
            // Update lastSent only if actual send was successful
            if(data_len > 0 && sockets[fd].state == ESTABLISHED) {
                sockets[fd].lastSent = seq + data_len;
            }
            return SUCCESS;
        } 
        return FAIL;
    }
    
    // Send control packet
    error_t send_control_packet(socket_t fd, uint8_t flags, uint16_t seq, uint16_t ack) {
        dbg(TRANSPORT_CHANNEL, "Node %u: send_control_packet fd=%u flags=0x%x seq=%u ack=%u\n", TOS_NODE_ID, fd, flags, seq, ack);
        return send_data_packet(fd, NULL, 0, flags, seq, ack);
    }

    static void send_ack_if_allowed(socket_t fd) {
        if (tuple_bound(fd) && state_allows_ack(fd)) {
            send_control_packet(fd, ACK_FLAG, sockets[fd].lastSent, sockets[fd].lastRcvd);
        }
    }
    
    // Handle data reception
    error_t handle_data_reception(socket_t fd, transport_header* tcp_hdr, uint8_t* data, uint16_t data_len) {
        uint8_t seq_num = tcp_hdr->seq_num;
        uint8_t expected8 = (uint8_t)sockets[fd].lastRcvd;
        
        // Update effective window
        sockets[fd].effectiveWindow = tcp_hdr->window;
        dbg(TRANSPORT_CHANNEL, "seq_num: %u, nextExpected: %u\n", seq_num, sockets[fd].nextExpected);
        
        // Check if this is the next expected packet
        if(seq_eq(seq_num, expected8)) {
            // Calculate available space in receive buffer
            uint16_t available_space = SOCKET_BUFFER_SIZE - (sockets[fd].lastRcvd - sockets[fd].lastRead);
            dbg(TRANSPORT_CHANNEL, "lastRcvd: %u, lastRead: %u\n", sockets[fd].lastRcvd, sockets[fd].lastRead);
            if(data_len <= available_space && data_len > 0) {
                // Copy data to receive buffer (circular)
                uint16_t buffer_pos = sockets[fd].lastRcvd % SOCKET_BUFFER_SIZE;
                uint16_t first_chunk = (buffer_pos + data_len <= SOCKET_BUFFER_SIZE) ? data_len : SOCKET_BUFFER_SIZE - buffer_pos;
                
                memcpy(sockets[fd].rcvdBuff + buffer_pos, data, first_chunk);
                if(first_chunk < data_len) {
                    memcpy(sockets[fd].rcvdBuff, data + first_chunk, data_len - first_chunk);
                }
                
                sockets[fd].lastRcvd += data_len;
                sockets[fd].nextExpected += data_len;

                dbg(TRANSPORT_CHANNEL, "lastRcvd: %u, nextExpected: %u\n", (uint8_t)sockets[fd].lastRcvd, (uint8_t)sockets[fd].nextExpected);

                if (state_allows_ack(fd) && tuple_bound(fd)) {
                    send_control_packet(fd, ACK_FLAG, sockets[fd].lastSent, sockets[fd].lastRcvd);
                }
                
                dbg(TRANSPORT_CHANNEL, "Node %u: Stored %u bytes at seq=%u\n", TOS_NODE_ID, data_len, seq_num);
            }
        }
        else {
            dbg(TRANSPORT_CHANNEL, "Node %u: Seq mismatch! Got %u, Expected %u (fd %u)\n", TOS_NODE_ID, seq_num, sockets[fd].nextExpected, fd);
        }
        
        // Always send ACK
        dbg(TRANSPORT_CHANNEL, "Node %u: AFTER STORE - lastRcvd=%u, nextExpected=%u\n",
    TOS_NODE_ID, sockets[fd].lastRcvd, sockets[fd].nextExpected);
        return SUCCESS;
    }
    
    // Handle SYN packet
    socket_t handle_syn_packet(transport_header* tcp_hdr, uint16_t src_addr){
        socket_t listen_fd;
        socket_t existing_fd;
        socket_t new_fd;
        
        listen_fd = find_listener_socket(tcp_hdr->dest_port, TOS_NODE_ID);
        if(listen_fd == NULL_SOCKET){
            dbg(TRANSPORT_CHANNEL, "Node %u: No listener on port %u\n", TOS_NODE_ID, tcp_hdr->dest_port);
            return NULL_SOCKET;
        }

        existing_fd = find_socket_by_addr(tcp_hdr->dest_port, TOS_NODE_ID, tcp_hdr->src_port, src_addr);
        if (existing_fd != NULL_SOCKET) {
            if(sockets[existing_fd].state == SYN_RCVD /*&& !(tcp_hdr->flags & ACK_FLAG) && tcp_hdr->seq_num == 0*/){
                // RESEND SYN+ACK
                send_control_packet(existing_fd, SYN_FLAG | ACK_FLAG, sockets[existing_fd].lastSent, sockets[existing_fd].lastRcvd);
                // return existing_fd;
            }
            else{
                dbg(TRANSPORT_CHANNEL, "Node %u: Ignoring SYN on existing socket %u (state=%u)\n", TOS_NODE_ID, existing_fd, sockets[existing_fd].state);
                return existing_fd;
            }
        }
        
        new_fd = find_free_socket();
        if(new_fd == NULL_SOCKET){
            dbg(TRANSPORT_CHANNEL, "Node %u: No free socket for SYN\n", TOS_NODE_ID);
            return NULL_SOCKET;
        }

        dbg(TRANSPORT_CHANNEL, "Node %u: SYN PACKET RECEIVED: src=%u:%u dest=%u:%u flags=0x%x seq=%u\n", TOS_NODE_ID, src_addr, tcp_hdr->src_port, TOS_NODE_ID, tcp_hdr->dest_port, tcp_hdr->flags, tcp_hdr->seq_num);

        dbg(TRANSPORT_CHANNEL, "Node %u: Looking for listener on port %u, found: %u\n", TOS_NODE_ID, tcp_hdr->dest_port, listen_fd);

        // Initialize new socket
        sockets[new_fd].src = tcp_hdr->dest_port;
        sockets[new_fd].dest.port = tcp_hdr->src_port;
        sockets[new_fd].dest.addr = src_addr;
        sockets[new_fd].local_addr = TOS_NODE_ID;
        sockets[new_fd].state = SYN_RCVD;
        sockets[new_fd].flag = listen_fd;
        sockets[new_fd].lastRcvd = tcp_hdr->seq_num + 1;
        sockets[new_fd].lastRead = sockets[new_fd].lastRcvd;
        sockets[new_fd].lastSent = 2; // (uint8_t)call Random.rand16();
        sockets[new_fd].lastAck = sockets[new_fd].lastSent;
        sockets[new_fd].nextExpected = sockets[new_fd].lastRcvd;
        sockets[new_fd].effectiveWindow = tcp_hdr->window;
        advertisedWindow[new_fd] = SOCKET_BUFFER_SIZE;

        dbg(TRANSPORT_CHANNEL, "Node %u: SYN from Node %u for Port %u\n", TOS_NODE_ID, src_addr, tcp_hdr->dest_port);

        // Send SYN_ACK
        send_control_packet(new_fd, SYN_FLAG | ACK_FLAG, sockets[new_fd].lastSent, sockets[new_fd].lastRcvd);

        sockets[new_fd].lastSent++;

        sockets[new_fd].lastWritten = sockets[new_fd].lastSent;

        return new_fd;
    }

    void send_buffered_data(socket_t fd){
        uint8_t packets_sent = 0;
        uint8_t MAX_BURST = 8;  // Only send 2 packets per call

        if (!state_allows_data(fd) || !tuple_bound(fd)) return;
        
        while(sockets[fd].lastSent < sockets[fd].lastWritten && packets_sent < MAX_BURST) {
            uint16_t available_to_send = sockets[fd].lastWritten - sockets[fd].lastSent;
            uint16_t window_left = sockets[fd].effectiveWindow;
            uint16_t bytes_to_send;
            uint16_t send_pos;
            uint16_t send_chunk;
            uint8_t send_data[MAX_DATA_SIZE];
            
            if(available_to_send > window_left) {
                available_to_send = window_left;
            }
            if(available_to_send > MAX_DATA_SIZE) {
                bytes_to_send = MAX_DATA_SIZE;
            } else {
                bytes_to_send = available_to_send;
            }

            if(bytes_to_send == 0) {
                break;
            }

            // Pull bytes out of circular buffer
            send_pos = sockets[fd].lastSent % SOCKET_BUFFER_SIZE;
            send_chunk = (send_pos + bytes_to_send <= SOCKET_BUFFER_SIZE) ? bytes_to_send : (SOCKET_BUFFER_SIZE - send_pos);

            memcpy(send_data, sockets[fd].sendBuff + send_pos, send_chunk);
            if(send_chunk < bytes_to_send) {
                memcpy(send_data + send_chunk, sockets[fd].sendBuff, bytes_to_send - send_chunk);
            }

            if(send_data_packet(fd, send_data, bytes_to_send, ACK_FLAG, sockets[fd].lastSent, sockets[fd].nextExpected) != SUCCESS) {
                break;
            }

            // lastSent is already updated by send_data_packet
            sockets[fd].effectiveWindow -= bytes_to_send;
            packets_sent++;
        }
    }
    
    // Process received transport packet
    error_t process_transport_packet(uint8_t* payload, uint8_t len, uint16_t src_addr) {
        transport_header* tcp_hdr = (transport_header*)payload;
        uint8_t* data = (uint8_t*)payload + TRANSPORT_HEADER_SIZE;
        uint16_t data_len = tcp_hdr->len;
        socket_t fd;
        

        if(len < TRANSPORT_HEADER_SIZE + data_len){
            dbg(TRANSPORT_CHANNEL, "Node %u: Dropping packet, length %u < header size %u\n", TOS_NODE_ID, len, TRANSPORT_HEADER_SIZE);
            return FAIL;
        }

        dbg(TRANSPORT_CHANNEL, "Node %u: RX transport pkt src_port=%u dest_port=%u flags=0x%x seq=%u ack=%u\n", 
            TOS_NODE_ID,
            tcp_hdr->src_port,
            tcp_hdr->dest_port,
            tcp_hdr->flags,
            tcp_hdr->seq_num,
            tcp_hdr->ack_num);

        fd = find_socket_by_addr(tcp_hdr->dest_port, TOS_NODE_ID, tcp_hdr->src_port, src_addr);
        
        // --- Pure SYN for a NEW connection: must create child socket ---
        if ((tcp_hdr->flags & SYN_FLAG) && !(tcp_hdr->flags & ACK_FLAG)) {
            if (fd == NULL_SOCKET) {
                socket_t new_fd = handle_syn_packet(tcp_hdr, src_addr);
                dbg(TRANSPORT_CHANNEL, "Node %u: PURE SYN to %u:%u from %u:%u\n",
    TOS_NODE_ID, TOS_NODE_ID, tcp_hdr->dest_port, src_addr, tcp_hdr->src_port);
                if (new_fd == NULL_SOCKET) {
                    dbg(TRANSPORT_CHANNEL, "Node %u: No listener for SYN dest_port=%u\n", TOS_NODE_ID, tcp_hdr->dest_port);
                }
                return SUCCESS; // handled SYN (or rejected)
            }
            // SYN targeting an existing 4-tuple (dup): your existing branch is fine
        }

         // From here on, we MUST have a valid fd
        if (fd == NULL_SOCKET) {
            dbg(TRANSPORT_CHANNEL, "Node %u: No matching socket for non-SYN pkt, dropping\n", TOS_NODE_ID);
            return FAIL;
        }

        if ((tcp_hdr->flags & SYN_FLAG)) {
            if (fd != NULL_SOCKET) {
                // This is a duplicate SYN for an existing connection
                if (sockets[fd].state == SYN_RCVD && !(tcp_hdr->flags & ACK_FLAG)) {
                    dbg(TRANSPORT_CHANNEL, "Node %u: DUP SYN detected on socket %u — resending SYN+ACK\n", TOS_NODE_ID, fd);
                    send_control_packet(fd, SYN_FLAG | ACK_FLAG, sockets[fd].lastSent, sockets[fd].lastRcvd);
                    return SUCCESS;
                }
                if (sockets[fd].state == SYN_SENT && (tcp_hdr->flags & ACK_FLAG)) {
                    call TCPTimer.stop();
                    sockets[fd].state = ESTABLISHED;
                    sockets[fd].lastSent = 1;
                    sockets[fd].lastRcvd = tcp_hdr->seq_num + 1;
                    sockets[fd].nextExpected = sockets[fd].lastRcvd;
                    sockets[fd].lastRead = sockets[fd].lastRcvd;
                    // sockets[fd].lastAck = tcp_hdr->ack_num;
                    
                    // Send the final ACK of the 3-way handshakets[fd].lastSent, sockets[fd].nextExpected);
                    send_control_packet(fd, ACK_FLAG, sockets[fd].lastSent, sockets[fd].nextExpected);
                    dbg(TRANSPORT_CHANNEL, "Node %u: Connection ESTABLISHED socket %u (SYN-ACK received)\n", TOS_NODE_ID, fd);
                    return SUCCESS; // Return here to avoid dropping the packet later
                } 

                if (sockets[fd].state == ESTABLISHED && (tcp_hdr->flags & ACK_FLAG)) {
                    dbg(TRANSPORT_CHANNEL, "Node %u: Duplicate SYN-ACK on ESTABLISHED socket %u - resending ACK\n", TOS_NODE_ID, fd);
                    send_control_packet(fd, ACK_FLAG, sockets[fd].lastSent, sockets[fd].lastRcvd);
                    return SUCCESS;
                }

                if (sockets[fd].state == ESTABLISHED && !(tcp_hdr->flags & ACK_FLAG)) {
                    dbg(TRANSPORT_CHANNEL, "Node %u: Duplicate SYN on ESTABLISHED socket %u - resending SYN-ACK\n", TOS_NODE_ID, fd);
                    send_control_packet(fd, SYN_FLAG | ACK_FLAG, sockets[fd].lastSent, sockets[fd].lastRcvd);
                    return SUCCESS;
                }

                return SUCCESS;
            }

            if (!(tcp_hdr->flags & ACK_FLAG)) {
                // Pure SYN - new connection
                socket_t new_fd = handle_syn_packet(tcp_hdr, src_addr);
                dbg(TRANSPORT_CHANNEL, "Node %u: PURE SYN to %u:%u from %u:%u\n",
    TOS_NODE_ID, TOS_NODE_ID, tcp_hdr->dest_port, src_addr, tcp_hdr->src_port);
                if (new_fd != NULL_SOCKET) {
                    dbg(TRANSPORT_CHANNEL, "Node %u: Created new socket %u for SYN\n", TOS_NODE_ID, new_fd);
                }
                return SUCCESS;
            }
        }

        if ((tcp_hdr->flags & ACK_FLAG) && fd != NULL_SOCKET) {
            sockets[fd].effectiveWindow = tcp_hdr->window;
            if (sockets[fd].state == ESTABLISHED || sockets[fd].state == FIN_WAIT_1 || sockets[fd].state == FIN_WAIT_2 || sockets[fd].state == LAST_ACK) {
                remove_acked_packets(fd, tcp_hdr->ack_num);
                if ((uint8_t)(tcp_hdr->ack_num - sockets[fd].lastSent) > 0) {
                    sockets[fd].lastSent = tcp_hdr->ack_num;
                }
                sockets[fd].lastAck = tcp_hdr->ack_num;
                send_buffered_data(fd);
            }
        }

        // Handle data
        if (data_len > 0 && fd != NULL_SOCKET) {
            uint8_t seq = tcp_hdr->seq_num;
            uint8_t expected8 = (uint8_t)sockets[fd].lastRcvd;

            if (seq_in_window(seq, expected8, 128)) {
                
                // If the sequence number is exactly the next expected one, it's new data.
                if (seq_eq(seq, expected8)) {
                    // New in-order data (or first segment)
                    handle_data_reception(fd, tcp_hdr, data, data_len);
                }
                // If it's earlier, it's a duplicate that was already received.
                else if (seq_lt(seq, expected8)) {
                    dbg(TRANSPORT_CHANNEL,
                        "Node %u: Duplicate DATA seq=%u expected=%u — resending ACK\n",
                        TOS_NODE_ID, seq, sockets[fd].nextExpected);
                    send_ack_if_allowed(fd);
                    return SUCCESS;
                }
            }
            else {
                // Out-of-window data (too far ahead or too far behind)
                dbg(TRANSPORT_CHANNEL,
                    "Node %u: Out-of-window seq=%u expected=%u — dropping and resending ACK\n",
                    TOS_NODE_ID, seq, sockets[fd].nextExpected);
                send_ack_if_allowed(fd);
                return SUCCESS;
            }
        }

        if (fd == NULL_SOCKET) return FAIL;

        // State transitions
        switch(sockets[fd].state){
            case SYN_SENT:
                if((tcp_hdr->flags & SYN_FLAG) && (tcp_hdr->flags & ACK_FLAG)){
                    call TCPTimer.stop();
                    sockets[fd].state = ESTABLISHED;
                    sockets[fd].lastRcvd = tcp_hdr->seq_num + 1;
                    sockets[fd].nextExpected = sockets[fd].lastRcvd;
                    sockets[fd].lastAck = tcp_hdr->ack_num;
                    sockets[fd].effectiveWindow = tcp_hdr->window;
                    send_control_packet(fd, ACK_FLAG, sockets[fd].lastSent, sockets[fd].nextExpected);
                    dbg(TRANSPORT_CHANNEL, "Node %u: Connection established socket %u\n", TOS_NODE_ID, fd);
                }
                break;

            case SYN_RCVD:
                if(tcp_hdr->flags & ACK_FLAG){
                    call TCPTimer.stop();
                    sockets[fd].state = ESTABLISHED;
                    sockets[fd].lastSent = tcp_hdr->ack_num;
                    if((uint8_t)(tcp_hdr->ack_num - sockets[fd].lastSent) > 0){
                        sockets[fd].lastSent = tcp_hdr->ack_num; 
                    }
                    dbg(TRANSPORT_CHANNEL, "Node %u: Connection ESTABLISHED on socket %u\n", TOS_NODE_ID, fd);
                }
                break;

            case ESTABLISHED:
                if(tcp_hdr->flags & ACK_FLAG){
                    dbg(TRANSPORT_CHANNEL, "Node %u: Data processed successfully for socket %u\n", TOS_NODE_ID, fd);
                    // remove_acked_packets(fd, tcp_hdr->ack_num);
                    // if((uint8_t)(tcp_hdr->ack_num - sockets[fd].lastSent) > 0) {
                    //     sockets[fd].lastSent = tcp_hdr->ack_num; 
                    // }
                    // sockets[fd].lastAck = tcp_hdr->ack_num;
                    // send_buffered_data(fd);

                    if(tcp_hdr->flags & FIN_FLAG){
                        call TCPTimer.stop();
                        sockets[fd].state = CLOSE_WAIT;
                        sockets[fd].lastRcvd = tcp_hdr->seq_num + 1;
                        send_ack_if_allowed(fd);
                        dbg(TRANSPORT_CHANNEL, "Node %u: Received FIN socket %u\n", TOS_NODE_ID, fd);
                    }
                }
                break;

            case CLOSE_WAIT:
                if (tcp_hdr->flags & FIN_FLAG) {
                    // Peer is retransmitting FIN because they missed our ACK. Resend ACK.
                    dbg(TRANSPORT_CHANNEL, "Node %u: RX DUP FIN in CLOSE_WAIT - resending ACK\n", TOS_NODE_ID);
                    send_ack_if_allowed(fd);
                }
                break;

            case FIN_WAIT_1:
                if(tcp_hdr->flags & ACK_FLAG){
                    // sockets[fd].lastSent++;
                    sockets[fd].state = FIN_WAIT_2;
                }
                break;

            case FIN_WAIT_2:
                if(tcp_hdr->flags & FIN_FLAG){
                    call TCPTimer.stop();
                    sockets[fd].state = TIME_WAIT;
                    sockets[fd].lastRcvd = tcp_hdr->seq_num + 1;
                    send_ack_if_allowed(fd);
                    call TCPTimer.startOneShot(TIME_WAIT_PERIOD);
                }
                break;

            case LAST_ACK:
                if(tcp_hdr->flags & ACK_FLAG){
                    if (tcp_hdr->ack_num == sockets[fd].lastSent) {
                        call TCPTimer.stop();
                        sockets[fd].state = CLOSED;
                        dbg(TRANSPORT_CHANNEL, "Node %u: Connection closed socket %u\n", TOS_NODE_ID, fd);
                    }
                }
                break;
            default:
                break;
        }
        return SUCCESS;
    }
    
    // Transport Interface Commands
    command socket_t Transport.socket() {
        socket_t fd = find_free_socket();
        if(fd != NULL_SOCKET){
            dbg(TRANSPORT_CHANNEL, "Node %u: Created socket %u\n", TOS_NODE_ID, fd);
        }
        return fd;
    }
    
    command error_t Transport.bind(socket_t fd, socket_addr_t *addr){
        if(fd == NULL_SOCKET || fd >= MAX_NUM_OF_SOCKETS || addr == NULL) return FAIL;

        if(sockets[fd].state == CLOSED){
            if(addr->port != 0 && find_listener_socket(addr->port, TOS_NODE_ID) != NULL_SOCKET){
                return FAIL;
            }
            sockets[fd].src = addr->port;
            sockets[fd].local_addr = TOS_NODE_ID;
            dbg(TRANSPORT_CHANNEL, "Node %u: Bound socket %u to port %u\n", TOS_NODE_ID, fd, addr->port);
            return SUCCESS;
        }
        return FAIL;
    }
    
    command socket_t Transport.accept(socket_t fd){
        uint8_t i;
        if(fd == NULL_SOCKET || fd >= MAX_NUM_OF_SOCKETS || sockets[fd].state != LISTEN){
            return NULL_SOCKET;
        }

        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++){
            if(sockets[i].flag == fd && sockets[i].state == ESTABLISHED){
                sockets[i].flag = LISTENER_UNLINKED;
                dbg(TRANSPORT_CHANNEL, "Node %u: Accepted connection socket %u\n", TOS_NODE_ID, i);
                return i;
            }
        }
        return NULL_SOCKET;
    }
    
    command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen){
        uint16_t inFlight;
        uint16_t freeSpace;
        uint16_t bytes_to_buffer;
        uint16_t buffer_pos;
        uint16_t first_chunk;

        if(fd == NULL_SOCKET || fd >= MAX_NUM_OF_SOCKETS ||
           sockets[fd].state != ESTABLISHED) {
            return 0;
        }
        if(buff == NULL || bufflen == 0) {
            return 0;
        }

        inFlight = sockets[fd].lastWritten - sockets[fd].lastAck;
        if(inFlight >= SOCKET_BUFFER_SIZE) {
            // Our local send buffer is completely full
            return 0;
        }

        freeSpace = SOCKET_BUFFER_SIZE - inFlight;
        bytes_to_buffer = (bufflen > freeSpace) ? freeSpace : bufflen;

        // Copy into send buffer (circular)
        buffer_pos = sockets[fd].lastWritten % SOCKET_BUFFER_SIZE;
        first_chunk = (buffer_pos + bytes_to_buffer <= SOCKET_BUFFER_SIZE) ? bytes_to_buffer : (SOCKET_BUFFER_SIZE - buffer_pos);

        memcpy(sockets[fd].sendBuff + buffer_pos, buff, first_chunk);
        if(first_chunk < bytes_to_buffer) {
            memcpy(sockets[fd].sendBuff, buff + first_chunk, bytes_to_buffer - first_chunk);
        }

        sockets[fd].lastWritten += bytes_to_buffer;

        send_buffered_data(fd);

        dbg(TRANSPORT_CHANNEL, "Node %u: Wrote %u bytes socket %u\n", TOS_NODE_ID, bytes_to_buffer, fd);
        dbg(TRANSPORT_CHANNEL, "Node %u: Write buffered %u bytes, lastWritten=%u, lastAck=%u, inFlight=%u\n", 
        TOS_NODE_ID, bytes_to_buffer, sockets[fd].lastWritten, sockets[fd].lastAck, inFlight);
        return bytes_to_buffer;
    }
    
    command error_t Transport.receive(pack* package){
        // Not used – delivery is handled via IPForwarding.packReachedDest
        return SUCCESS;
    }
    
    command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen){
        // Calculate available data
        uint16_t available_data = sockets[fd].lastRcvd - sockets[fd].lastRead;
        uint16_t bytes_to_read;
        uint16_t buffer_pos;
        uint16_t first_chunk;
        
        if(fd == NULL_SOCKET || fd >= MAX_NUM_OF_SOCKETS) {
            return 0;
        }

        dbg(TRANSPORT_CHANNEL, "Node %u: READ REQUEST - lastRcvd=%u, lastRead=%u, available=%u\n",
        TOS_NODE_ID, sockets[fd].lastRcvd, sockets[fd].lastRead, 
        sockets[fd].lastRcvd - sockets[fd].lastRead);
        bytes_to_read = (bufflen > available_data) ? available_data : bufflen;

        buffer_pos = sockets[fd].lastRead % SOCKET_BUFFER_SIZE;
        first_chunk = (buffer_pos + bytes_to_read <= SOCKET_BUFFER_SIZE) ? bytes_to_read :SOCKET_BUFFER_SIZE - buffer_pos;

        memcpy(buff, sockets[fd].rcvdBuff + buffer_pos, first_chunk);
        if(first_chunk < bytes_to_read) {
            memcpy(buff + first_chunk, sockets[fd].rcvdBuff, bytes_to_read - first_chunk);
        }

        sockets[fd].lastRead += bytes_to_read;
        advertisedWindow[fd] = SOCKET_BUFFER_SIZE - (sockets[fd].lastRcvd - sockets[fd].lastRead);

        if (bytes_to_read > 0 && state_allows_ack(fd) && tuple_bound(fd)) {
            send_control_packet(fd, ACK_FLAG, sockets[fd].lastSent, sockets[fd].lastRcvd);
        }
        
        dbg(GENERAL_CHANNEL, "bytes_to_read: %u\n", bytes_to_read);  
        return bytes_to_read;
    }
    
    command error_t Transport.connect(socket_t fd, socket_addr_t * addr){
        if(fd == NULL_SOCKET || fd >= MAX_NUM_OF_SOCKETS || addr == NULL) return FAIL;
        
        if(sockets[fd].state == CLOSED){
            if(sockets[fd].src == 0) {
                dbg(TRANSPORT_CHANNEL, "Node %u: Socket %u has no source port!\n", TOS_NODE_ID, fd);
                return FAIL;
            }
            sockets[fd].dest.port = addr->port;
            sockets[fd].dest.addr = addr->addr;
            sockets[fd].local_addr = TOS_NODE_ID;
            sockets[fd].state = SYN_SENT;
            sockets[fd].lastSent = 0; // (uint8_t)call Random.rand16();
            sockets[fd].nextExpected = 1;
            sockets[fd].lastAck = 0;
            sockets[fd].lastWritten = 1;
            sockets[fd].lastRcvd = 0;
            sockets[fd].effectiveWindow = SOCKET_BUFFER_SIZE;
            advertisedWindow[fd] = SOCKET_BUFFER_SIZE;
            sockets[fd].RTT = 150;

            dbg(TRANSPORT_CHANNEL, "Node %u: Socket %u - local=%u:%u, remote=%u:%u\n",
            TOS_NODE_ID, fd, TOS_NODE_ID, sockets[fd].src, addr->addr, addr->port);

            if(send_control_packet(fd, SYN_FLAG, sockets[fd].lastSent, 0) == SUCCESS){
                sockets[fd].lastSent++;
                call TCPTimer.startOneShot(RTO);
                return SUCCESS;
            }
            sockets[fd].state = CLOSED;
            return FAIL;
        }
        return FAIL;
    }
    
    command error_t Transport.close(socket_t fd){
        if(fd == NULL_SOCKET || fd >= MAX_NUM_OF_SOCKETS) return FAIL;

        dbg(TRANSPORT_CHANNEL, "Node %u: Closing socket %u state=%u\n", TOS_NODE_ID, fd, sockets[fd].state);

        switch(sockets[fd].state){
            case ESTABLISHED:
                sockets[fd].state = FIN_WAIT_1;
                send_control_packet(fd, FIN_FLAG | ACK_FLAG, sockets[fd].lastSent, sockets[fd].lastRcvd);
                sockets[fd].lastSent++;
                call TCPTimer.startOneShot(RTO);
                break;
            case CLOSE_WAIT:
                sockets[fd].state = LAST_ACK;
                send_control_packet(fd, FIN_FLAG | ACK_FLAG, sockets[fd].lastSent, sockets[fd].nextExpected);
                sockets[fd].lastSent++;
                call TCPTimer.startOneShot(RTO);
                break;
            case SYN_SENT:
            case LISTEN:
                sockets[fd].state = CLOSED;
                break;
            default:
                break;
        }
        return SUCCESS;
    }
    
    command error_t Transport.release(socket_t fd){
        if(fd != NULL_SOCKET && fd < MAX_NUM_OF_SOCKETS){
            sockets[fd].state = CLOSED;
            dbg(TRANSPORT_CHANNEL, "Node %u: Released socket %u\n", TOS_NODE_ID, fd);
        }
        return SUCCESS;
    }
    
    command error_t Transport.listen(socket_t fd){
        if(fd == NULL_SOCKET || fd >= MAX_NUM_OF_SOCKETS) return FAIL;

        if(sockets[fd].state == CLOSED && sockets[fd].src != 0){
            sockets[fd].state = LISTEN; 
            dbg(TRANSPORT_CHANNEL, "Node %u: Listening socket %u port %u\n", TOS_NODE_ID, fd, sockets[fd].src);
            return SUCCESS;
        }
        return FAIL;
    }
  
    // Timer event for retransmissions
    event void TCPTimer.fired(){
        uint8_t i;
        bool restartTimer = FALSE;
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++){
            // Handle SYN Retransmission
            if (sockets[i].state == SYN_SENT) {
                dbg(TRANSPORT_CHANNEL, "Node %u: Retransmitting SYN for socket %u\n", TOS_NODE_ID, i);
                // Retransmit SYN. Note: sequence number is lastSent-1 because connect() increments lastSent.
                send_control_packet(i, SYN_FLAG, sockets[i].lastSent - 1, 0);
                
                restartTimer = TRUE;
                continue;
            }

            // Handle FIN Retransmission
            if (sockets[i].state == FIN_WAIT_1 || sockets[i].state == LAST_ACK) {
                dbg(TRANSPORT_CHANNEL, "Node %u: Retransmitting FIN for socket %u\n", TOS_NODE_ID, i);
                send_control_packet(i, FIN_FLAG | ACK_FLAG, sockets[i].lastSent - 1, sockets[i].nextExpected);
                restartTimer = FALSE;
                continue;
            }

            if(retransmitHead[i] != retransmitTail[i]) {
                uint16_t seq = retransmitSeq[i][retransmitHead[i]];
                uint16_t data_len = retransmitLen[i][retransmitHead[i]];
               
                // Extract data from send buffer
                uint8_t retransmit_data[MAX_DATA_SIZE];
                uint16_t buffer_pos = seq % SOCKET_BUFFER_SIZE;
                uint16_t first_chunk = (buffer_pos + data_len <= SOCKET_BUFFER_SIZE) ? data_len : SOCKET_BUFFER_SIZE - buffer_pos;

                if(is_sequence_acknowledged(i, seq)) {
                    retransmitHead[i] = (retransmitHead[i] + 1) % RETRANSMIT_QUEUE_SIZE;
                    continue;
                }
                
                memcpy(retransmit_data, sockets[i].sendBuff + buffer_pos, first_chunk);
                if(first_chunk < data_len) {
                    memcpy(retransmit_data + first_chunk, sockets[i].sendBuff, data_len - first_chunk);
                }
               
                dbg(TRANSPORT_CHANNEL, "Node %u: Retransmit %u bytes seq=%u socket %u\n", TOS_NODE_ID, data_len, seq, i);
                   
                send_data_packet(i, retransmit_data, data_len, ACK_FLAG, seq, sockets[i].nextExpected);

                retransmitTime[i][retransmitHead[i]] = call TCPTimer.getNow();

                restartTimer = FALSE;

            }
        }
        if(restartTimer){
            call TCPTimer.startOneShot(RTO);
        }
    }

  
    // Network packet reception
    event void IPForwarding.packReachedDest(pack* linkPkt, uint8_t len){
        dbg(TRANSPORT_CHANNEL, "Node %u: Receive.receive protocol=%u len=%u\n", TOS_NODE_ID, linkPkt->protocol, len);

            if(linkPkt->protocol == PROTOCOL_IP) {
                ip_header* ip_hdr = (ip_header*)(linkPkt->payload);

                if (ip_hdr->dest != TOS_NODE_ID) {
                    return;
                }

                dbg(TRANSPORT_CHANNEL, "Node %u: IP packet src=%u dest=%u protocol=%u\n", TOS_NODE_ID, ip_hdr->src, ip_hdr->dest, ip_hdr->protocol);

                if(ip_hdr->protocol == PROTOCOL_TCP){
                    uint8_t* tcp_payload = (uint8_t*)(linkPkt->payload + IP_HEADER_LENGTH);
                    uint8_t tcp_len = len - IP_HEADER_LENGTH;
                    dbg(TRANSPORT_CHANNEL, "Node %u: TCP packet! len=%u\n", TOS_NODE_ID, tcp_len);

                    process_transport_packet(tcp_payload, tcp_len, ip_hdr->src);
                }
            }
        
    }
    command uint8_t Transport.getState(socket_t fd){
        if(fd == NULL_SOCKET || fd >= MAX_NUM_OF_SOCKETS) return CLOSED;
        return sockets[fd].state;
    }
}