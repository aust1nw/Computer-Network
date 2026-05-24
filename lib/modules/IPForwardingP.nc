#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/ip_header.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendinfo.h"
#include "../../includes/channels.h"
#define MAX_OUTGOING_PACKETS 10

generic module IPForwardingP(){
    provides interface IPForwarding;
    
    uses interface LSRouting;
    uses interface Packet;
    uses interface Receive as IPReceive;
    uses interface SimpleSend as Send;
    uses interface Queue<pack*>;
    uses interface Pool<pack>;
}

implementation{
    bool initialized = FALSE;
    static uint16_t packetCounter = 0;
    static pack outgoingQueue[MAX_OUTGOING_PACKETS];
    static uint8_t queueHead = 0;
    static uint8_t queueTail = 0;

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t *payload, uint8_t length){
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = packetCounter++;
        Package->protocol = protocol;

        if(payload != NULL && length > 0){
            memcpy(Package->payload, payload, length);
        }
    }

    void makeIPHeader(ip_header *header, uint8_t src, uint8_t dest, uint8_t TTL, uint8_t protocol){
        header->src = (uint8_t)src;
        header->dest = (uint8_t)dest;
        header->TTL = TTL;
        header->protocol = protocol;
    }

    command void IPForwarding.start(){
        call LSRouting.start();
    }

    task void sendQueuedPackets(){
        while(queueHead != queueTail){
            pack packetToSend;
            uint16_t nextHop;
            
            // Dequeue the packet
            memcpy(&packetToSend, &outgoingQueue[queueHead], sizeof(pack));
            nextHop = outgoingQueue[queueHead].dest; // Retrieve the stored nextHop
            
            queueHead = (queueHead + 1) % MAX_OUTGOING_PACKETS;
            
            // Send the packet. This runs outside the previous event context.
            if(call Send.send(packetToSend, nextHop) != SUCCESS){
                // If the send fails (e.g., buffer busy), log it, but do not re-enqueue
                // or send immediately to avoid re-introducing the crash risk.
            }
        }
    }

    error_t enqueuePacket(pack* p, uint16_t nextHop){
        uint8_t nextTail = (queueTail + 1) % MAX_OUTGOING_PACKETS;
            
        if (nextTail == queueHead) {
            // Queue is full
            return FAIL;
        }
            
        // Copy the entire packet structure (including payload)
        memcpy(&outgoingQueue[queueTail], p, sizeof(pack)); 
        outgoingQueue[queueTail].dest = nextHop; // Use the 'dest' field to store nextHop temporarily
            
        queueTail = nextTail;
            
        // Post the task to run when the scheduler is idle, breaking the recursion
        post sendQueuedPackets();
            
        return SUCCESS;
    }

    command error_t IPForwarding.sendPing(uint16_t dest, uint8_t* payload, uint8_t len){
        pack ipPacket;
        ip_header ipHdr;
        uint8_t combinedPayload[PACKET_MAX_PAYLOAD_SIZE];
        uint16_t nextHop;
        uint8_t effective_len = len;

        if(dest == 0 || dest == TOS_NODE_ID){
            // dbg(GENERAL_CHANNEL, "Node %u: Invalid destination\n", TOS_NODE_ID);
            return FAIL;
        }

        nextHop = call LSRouting.getBestNextHop(dest);
        // dbg(GENERAL_CHANNEL, "Node %u: Sending ping - final dest=%u, got nextHop=%u\n", TOS_NODE_ID, dest, nextHop);

        if(nextHop == 0 || nextHop >= MAX_NODES){
            return FAIL;
        }

        makeIPHeader(&ipHdr, TOS_NODE_ID, dest, DEFAULT_TTL, PROTOCOL_PING);

        if(IP_HEADER_LENGTH + len > PACKET_MAX_PAYLOAD_SIZE){
            effective_len = PACKET_MAX_PAYLOAD_SIZE - IP_HEADER_LENGTH;
        }

        // Combine IP header + payload
        memcpy(combinedPayload, (uint8_t*)&ipHdr, IP_HEADER_LENGTH);
        if(payload != NULL && effective_len > 0){
            memcpy(combinedPayload + IP_HEADER_LENGTH, payload, effective_len);
        }
        // Create link-layer packet
        makePack(&ipPacket, TOS_NODE_ID, nextHop, DEFAULT_TTL, PROTOCOL_IP, 0, combinedPayload, IP_HEADER_LENGTH + effective_len);

        // dbg(GENERAL_CHANNEL, "Node %u: Sending ping to %u via next hop %u\n", TOS_NODE_ID, dest, nextHop);
        
        // dbg(GENERAL_CHANNEL, "Sending to %u\n", nextHop);
        call Send.send(ipPacket, nextHop);

        return SUCCESS;
    }

    command error_t IPForwarding.sendTCP(uint16_t dest, uint8_t* payload, uint8_t len){
        pack ipPacket;
        ip_header ipHdr;
        uint8_t combinedPayload[PACKET_MAX_PAYLOAD_SIZE];
        uint16_t nextHop;
        uint8_t effective_len = len;

        if(dest == 0 || dest == TOS_NODE_ID){
            return FAIL;
        }

        nextHop = call LSRouting.getBestNextHop(dest);
        // dbg(GENERAL_CHANNEL, "Node %u: Sending TCP - final dest=%u, nextHop=%u\n", TOS_NODE_ID, dest, nextHop);

        if(nextHop == 0 || nextHop >= MAX_NODES){
            return FAIL;
        }

        makeIPHeader(&ipHdr, TOS_NODE_ID, dest, DEFAULT_TTL, PROTOCOL_TCP);

        if(IP_HEADER_LENGTH + len > PACKET_MAX_PAYLOAD_SIZE){
            effective_len = PACKET_MAX_PAYLOAD_SIZE - IP_HEADER_LENGTH;
        }

        // Combine IP header + payload
        memcpy(combinedPayload, (uint8_t*)&ipHdr, IP_HEADER_LENGTH);
        if(payload != NULL && effective_len > 0){
            memcpy(combinedPayload + IP_HEADER_LENGTH, payload, effective_len);
        }
        
        // Create link-layer packet
        makePack(&ipPacket, TOS_NODE_ID, nextHop, DEFAULT_TTL, PROTOCOL_IP, 0, combinedPayload, IP_HEADER_LENGTH + effective_len);

        // dbg(GENERAL_CHANNEL, "Node %u: Sending TCP to %u via %u\n", TOS_NODE_ID, dest, nextHop);
        
        if (enqueuePacket(&ipPacket, nextHop) == SUCCESS) {
            return SUCCESS;
        }
        return FAIL;
    }
    
    error_t forwardPacket(pack* originalPkt, ip_header* ipHdr, uint8_t* payload, uint8_t len){
        uint16_t dest = ipHdr->dest;
        pack forwardPack;
        ip_header newHdr;
        uint16_t nextHop;
        uint8_t combinedPayload[PACKET_MAX_PAYLOAD_SIZE];
        
        // dbg(GENERAL_CHANNEL, "Node %u: Forwarding packet src=%u dest=%u\n", TOS_NODE_ID, ipHdr->src, ipHdr->dest);

        nextHop = call LSRouting.getBestNextHop(dest);
        if(nextHop == 0){
            // dbg(GENERAL_CHANNEL, "Node %u: No route to %u\n", TOS_NODE_ID, dest);
            return FAIL;
        }

        // Create modified IP header in network byte order
        newHdr.src = ipHdr->src;      
        newHdr.dest = ipHdr->dest;    
        newHdr.protocol = ipHdr->protocol;
        newHdr.TTL = ipHdr->TTL - 1;
        

        // Get next hop using the FINAL destination from IP header
        // dbg(GENERAL_CHANNEL, "Node %u: Forwarding to dest=%u via nextHop=%u\n", TOS_NODE_ID, newHdr.dest, nextHop);

        // Loop detection
        if(nextHop == originalPkt->src){
            dbg(GENERAL_CHANNEL, "Node %u: Loop detected\n", TOS_NODE_ID);
            return FAIL;
        }

        if(nextHop == TOS_NODE_ID){
            dbg(GENERAL_CHANNEL, "Node %u: Loop detected - next hop is myself\n", TOS_NODE_ID);
            return FAIL;
        }

        // Check payload size
        if(IP_HEADER_LENGTH + len > PACKET_MAX_PAYLOAD_SIZE){
            return FAIL;
        }

        // Serialize the MODIFIED IP header
        memcpy(combinedPayload, &newHdr, IP_HEADER_LENGTH);
        
        // Copy the original payload
        if(payload != NULL && len > 0){
            memcpy(combinedPayload + IP_HEADER_LENGTH, payload, len);
        }

        // Create link-layer packet
        makePack(&forwardPack, TOS_NODE_ID, nextHop, MAX_TTL, PROTOCOL_IP, originalPkt->seq, combinedPayload, IP_HEADER_LENGTH + len);

        // dbg(GENERAL_CHANNEL, "Node %u: Forwarding to nextHop %u\n", TOS_NODE_ID, nextHop);
        if (enqueuePacket(&forwardPack, nextHop) == SUCCESS) {
            // dbg(GENERAL_CHANNEL, "Node %u: Forwarding to nextHop %u\n", TOS_NODE_ID, nextHop); [cite: 325]
            return SUCCESS;
        }
        return FAIL;
    }

    event message_t* IPReceive.receive(message_t* msg, void* payload, uint8_t len){
        pack* linkPkt;
        ip_header* ipHdr;
        uint8_t ipSrc;
        uint8_t ipDest;
        uint8_t ipTTL;
        uint8_t* dataPayload;
        uint8_t dataLen;
        uint8_t payloadOffset;
        uint8_t payloadTotal;   

        if(len < sizeof(pack)){
            return msg;
        }

        linkPkt = (pack*)payload;

        if(linkPkt->protocol != PROTOCOL_IP){
            return msg;
        }
        
        ipHdr = (ip_header*)(linkPkt->payload);
        ipSrc = linkPkt->src;
        ipDest = ipHdr->dest;
        ipTTL = ipHdr->TTL;
        
        payloadOffset = sizeof(pack) - PACKET_MAX_PAYLOAD_SIZE;
        payloadTotal = len - payloadOffset;

        // Drop packets I sent (avoid infinite loops)
        if (ipSrc == TOS_NODE_ID){
            return msg;
        }

        // Drop if TTL expired
        if (ipTTL <= 1) {
            // dbg(GENERAL_CHANNEL, "Node %u: TTL expired, dropping\n", TOS_NODE_ID);
            return msg;
        }

        if(payloadTotal < IP_HEADER_LENGTH){
            return msg;
        }

        dataPayload = (uint8_t*)(linkPkt->payload + IP_HEADER_LENGTH);
        dataLen = payloadTotal - IP_HEADER_LENGTH;

        if (ipDest == TOS_NODE_ID) {
            // dbg(GENERAL_CHANNEL, "Node %u: Packet is for me! protocol=%u\n", TOS_NODE_ID, ipProtocol);
            signal IPForwarding.packReachedDest(linkPkt, payloadTotal);
            return msg;
        }

        if (ipTTL <= 1) {
            dbg(GENERAL_CHANNEL, "Node %u: TTL expired, dropping\n", TOS_NODE_ID);
            return msg;
        }
        // dbg(GENERAL_CHANNEL,"Node %u: Forwarding packet to final dest=%u\n", TOS_NODE_ID, ipDest);

        forwardPacket(linkPkt, ipHdr, dataPayload, dataLen);

        return msg;
    }
}