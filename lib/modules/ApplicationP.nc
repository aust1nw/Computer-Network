#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/socket.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendinfo.h"
#include "../../includes/channels.h"
#include "../../includes/ring.h"
#include "../../includes/user.h"

#define CHAT_SERVER_NODE 1
#define CHAT_SERVER_PORT 41
#define CHAT_MAX_USERS 5
#define CHAT_MAX_NAME 16

generic module ApplicationP(){
    provides interface Application;

    uses interface Transport;
    uses interface Timer<TMilli> as Timer1;
}

implementation{
    bool isServer = FALSE;
    bool isClient = FALSE;
    socket_t serverFd = NULL_SOCKET;
    socket_t clientFd = NULL_SOCKET;
    uint16_t transferSize = 0;
    uint16_t counter = 0;
    uint8_t clientState = 0; // 0=idle, 1=connecting, 2=sending, 3=closing
    socket_t acceptedSockets[5];
    uint8_t numAccepted = 0;
    uint8_t connect_attempts;
    uint16_t value;

    // For Project 4
    bool chatServer = FALSE;
    bool chatClient = FALSE;
    socket_t chatListenFd = NULL_SOCKET; 
    socket_t chatCliFd = NULL_SOCKET; 
    socket_t chatFds[CHAT_MAX_USERS]; 
    uint8_t  chatN = 0;
    ring_t srvIn[CHAT_MAX_USERS];
    ring_t cliIn = { .w=0, .r=0 };
    user_t users[CHAT_MAX_USERS];

    static void ring_push(ring_t* rb, const uint8_t* d, uint16_t n){
        uint16_t i;
        for(i = 0 ; i < n; i++){ 
            rb->buf[(rb->w++) & 0xFF] = d[i]; 
        }
    }

    static bool ring_pop_line(ring_t* rb, char* out, uint16_t max){
        uint16_t i = rb->r;
        uint16_t k;
        while(i != rb->w){
            uint8_t c = rb->buf[i & 0xFF];
            if(c=='\r' && ((i+1)!=rb->w) && rb->buf[(i+1)&0xFF]=='\n'){
                uint16_t n = (uint16_t)(i - rb->r);
                if(n >= max) n = max-1;
                for(k = 0; k < n; k++){
                    out[k] = rb->buf[(rb->r + k) & 0xFF];
                }
                out[n]='\0';
                rb->r = (uint16_t)(i + 2);
                return TRUE;
            }
            i++;
        }
        return FALSE;
    }

    static uint16_t sendLine(socket_t fd, const char* s){
        char buf[160]; 
        uint16_t n = 0;
        uint16_t sent;

        while(s[n] && n < sizeof(buf)-2){ 
            buf[n]=s[n]; 
            n++; 
        }

        buf[n++] = '\r'; 
        buf[n++] = '\n';

        sent = 0;
        while(sent < n){
            uint16_t w = call Transport.write(fd, (uint8_t*)buf + sent, n - sent);
            if (w == 0) break;
            sent += w;
        }
        return sent;
    }

    static uint8_t find_user_index_by_fd(socket_t fd){
        uint8_t i;
        for(i = 0; i < chatN; i++){ 
            if(chatFds[i]==fd) return i;
        }
        return 0xFF;
    }

    static const char* safe_name(uint8_t idx){
        if(idx >= CHAT_MAX_USERS || !users[idx].used || users[idx].name[0]==0) return "unknown";
        return users[idx].name;
    }

    static bool name_in_use(const char* nm, uint8_t except_idx){
        uint8_t i;
        for(i = 0; i < chatN; i++){
            uint8_t a = 0;
            if (i == except_idx || !users[i].used) continue;
            // compare strings
            while(users[i].name[a] && nm[a] && users[i].name[a] == nm[a]){ 
                a++;
            }
            if(users[i].name[a] == 0 && nm[a] == 0) return TRUE;
        }
        return FALSE;
    }

    static void ensure_unique_name(const char* desired, char* out){
        uint8_t suffix = 2;
        uint8_t i = 0;

        for(i = 0; i < CHAT_MAX_NAME - 1 && desired[i]; i++){
            out[i] = desired[i];
        }

        out[i] = 0;

        while(name_in_use(out, 0xFF)){
            char tmp[CHAT_MAX_NAME];
            uint8_t p = 0, q = 0;
            while(desired[p] && p < CHAT_MAX_NAME - 1){ 
                tmp[p] = desired[p]; 
                p++; 
            }
            if (p < CHAT_MAX_NAME - 1) tmp[p++] = '-';
            if (p < CHAT_MAX_NAME - 1) {
                uint8_t digit = (suffix <= 9) ? suffix : 9;
                tmp[p++] = '0' + digit;
            }
            tmp[(p < CHAT_MAX_NAME) ? p : (CHAT_MAX_NAME - 1)] = 0;

            for(q = 0; q < CHAT_MAX_NAME; q++){ 
                out[q] = tmp[q]; 
                if(!tmp[q]) break; 
            }
            out[CHAT_MAX_NAME - 1] = 0;

            suffix++;
            if(suffix > 15) break;
        }
    }

    static void send_to_all(const char* line){
        uint8_t i;
        for(i = 0; i < chatN; i++){
            if (users[i].used) sendLine(chatFds[i], line);
        }
    }

    static void send_to_all_except(uint8_t except_idx, const char* line){
        uint8_t i;
        for(i = 0; i < chatN; i++){
            if (i == except_idx) continue;
            if (users[i].used) sendLine(chatFds[i], line);
        }
    }

    static void server_teardown_index(uint8_t idx){
        char msg[64];
        if(idx >= chatN || !users[idx].used) return;

        if(users[idx].name[0]){
            // "server: <name> left"
            uint8_t p = 0;
            const char* a = "server: ";
            while(*a && p < sizeof(msg)-1){ 
                msg[p++] = *a++;
            }
            a = users[idx].name;
            while(*a && p < sizeof(msg)-1){ 
                msg[p++] = *a++;
            }
            a = " left";
            while(*a && p < sizeof(msg)-1){ 
                msg[p++] = *a++;
            }
            msg[(p < sizeof(msg)) ? p : (sizeof(msg)-1)] = 0;
            send_to_all_except(idx, msg);
        }

        call Transport.close(chatFds[idx]);

        if(idx != chatN - 1){
            chatFds[idx] = chatFds[chatN - 1];
            srvIn[idx] = srvIn[chatN - 1];
            users[idx] = users[chatN - 1];
        }
        chatN--;
    }

    static void server_handle_line(uint8_t i, const char* line){
        uint16_t pos = 0;
        while(line[pos] == ' ' || line[pos] == '\t'){
            pos++;
        }

        // match "hello <name> <port>"
        if(line[pos]=='h' && line[pos+1]=='e' && line[pos+2]=='l' && line[pos+3]=='l' && line[pos+4]=='o' && (line[pos+5]==0 || line[pos+5]==' ' || line[pos+5]=='\t')){
            // parse name
            char want[CHAT_MAX_NAME];
            char uniq[CHAT_MAX_NAME];
            char buf[64];
            const char* s1 = "server: welcome ";
            uint8_t wn = 0;
            uint8_t j, p;
            
            pos += 5;
            while(line[pos]==' ' || line[pos]=='\t'){
                pos++;
            }
            while(line[pos] && line[pos] != ' ' && line[pos] != '\t' && wn < CHAT_MAX_NAME-1){
                want[wn++] = line[pos++];
            }
            want[wn] = 0;

            if(want[0] == 0){
                sendLine(chatFds[i], "server: usage hello <name> <port>");
                return;
            }

            // parse port
            while(line[pos]==' ' || line[pos]=='\t'){
                pos++;
            }
            // skip digits
            while(line[pos]>='0' && line[pos]<='9'){
                pos++;
            }
            // ensure unique and store
            ensure_unique_name(want, uniq);

            j = 0;
            while(uniq[j] && j < CHAT_MAX_NAME-1){ 
                users[i].name[j]=uniq[j]; j++; 
            }
            users[i].name[j]=0;

            // greet and broadcast join
            p = 0;
            while(*s1 && p < sizeof(buf)-1){
                buf[p++] = *s1++;
            }
            s1 = users[i].name;
            while(*s1 && p < sizeof(buf)-1){
                buf[p++] = *s1++;
            }
            buf[(p < sizeof(buf)) ? p : (sizeof(buf)-1)] = 0;
            sendLine(chatFds[i], buf);

            p = 0; 
            s1 = "server: "; 
            while(*s1 && p<sizeof(buf)-1){
                buf[p++]=*s1++;
            }
            s1 = users[i].name;   
            while (*s1 && p<sizeof(buf)-1){
                buf[p++]=*s1++;
            }
            s1 = " joined";       
            while(*s1 && p<sizeof(buf)-1){
                buf[p++]=*s1++;
            }
            buf[(p < sizeof(buf)) ? p : (sizeof(buf)-1)] = 0;
            send_to_all_except(i, buf);

            return;
        }

        // match "msg <text>"
        if(line[pos]=='m' && line[pos+1]=='s' && line[pos+2]=='g' && (line[pos+3]==0 || line[pos+3]==' ' || line[pos+3]=='\t')){
            char out[128]; uint8_t p=0;
            const char* nm = (users[i].name[0] ? users[i].name : "anon");

            pos += 3;
            while(line[pos]==' ' || line[pos]=='\t'){
                pos++;
            }
            // prefix with "<name>: "
            while(*nm && p < sizeof(out)-1){
                out[p++] = *nm++;
            }
            if(p < sizeof(out)-1) out[p++] = ':';
            if(p < sizeof(out)-1) out[p++] = ' ';

            while(line[pos] && p < sizeof(out)-1){
                out[p++] = line[pos++];
            }
            out[(p < sizeof(out)) ? p : (sizeof(out)-1)] = 0;

            send_to_all(out);
            return;
        }

        // match "listusr"
        if(line[pos]=='l' && line[pos+1]=='i' && line[pos+2]=='s' && line[pos+3]=='t' && line[pos+4]=='u' && line[pos+5]=='s' && line[pos+6]=='r'){
            char listBuf[128];
            uint8_t p = 0;
            uint8_t k;
            const char* prefix = "listUsrRply ";

            while(*prefix && p < sizeof(listBuf)-1){
                listBuf[p++] = *prefix++;
            }
            for(k = 0; k < chatN; k++){
                if(users[k].used && users[k].name[0]){
                    uint8_t n = 0;
                    
                    if(p > 12){ 
                        if(p < sizeof(listBuf)-1) listBuf[p++] = ',';
                        if(p < sizeof(listBuf)-1) listBuf[p++] = ' ';
                    }
                    
                    while(users[k].name[n] && p < sizeof(listBuf)-1){
                        listBuf[p++] = users[k].name[n++];
                    }
                }
            }
            listBuf[p] = 0; // Null terminate
            
            // Send reply ONLY to the requester
            sendLine(chatFds[i], listBuf);
            return;
        }

        if(line[pos]=='w' && line[pos+1]=='h' && line[pos+2]=='i' && line[pos+3]=='s' && line[pos+4]=='p' && line[pos+5]=='e' && line[pos+6]=='r'){
            char targetName[CHAT_MAX_NAME];
            char out[128];
            uint8_t tn = 0;
            uint8_t k;
            bool found = FALSE;
            
            pos += 7;
            while(line[pos]==' ' || line[pos]=='\t'){
                pos++; // skip spaces
            }

            // Parse the target username
            while(line[pos] && line[pos]!=' ' && line[pos]!='\t' && tn < CHAT_MAX_NAME-1){
                targetName[tn++] = line[pos++];
            }
            targetName[tn] = 0;
            
            if(tn == 0){
                sendLine(chatFds[i], "server: usage whisper <username> <message>");
                return;
            }

            // Find the target user
            for(k = 0; k < chatN; k++){
                if(users[k].used && strcmp(users[k].name, targetName) == 0){
                    // Construct the message "whisper from <sender>: <msg>"
                    uint8_t p = 0;
                    const char* sender = users[i].name;
                    const char* prefix = "whisper from ";

                    found = TRUE;
                    
                    while(*prefix && p < sizeof(out)-1){
                        out[p++] = *prefix++;
                    }
                    while(*sender && p < sizeof(out)-1){
                        out[p++] = *sender++;
                    }
                    if(p < sizeof(out)-1) out[p++] = ':';
                    if(p < sizeof(out)-1) out[p++] = ' ';
                    
                    // Skip whitespace after target name in input line
                    while(line[pos]==' ' || line[pos]=='\t'){
                        pos++;
                    }
                    
                    // Append the actual message content
                    while(line[pos] && p < sizeof(out)-1){ 
                        out[p++] = line[pos++];
                    }
                    out[p] = 0;
                    
                    // Send to target
                    sendLine(chatFds[k], out);
                     
                    break;
                }
            }
            
            if(!found){
                sendLine(chatFds[i], "server: user not found");
            }
            return;
        }

        // match "quit"
        if(line[pos]=='q' && line[pos+1]=='u' && line[pos+2]=='i' && line[pos+3]=='t' && (line[pos+4]==0 || line[pos+4]==' ' || line[pos+4]=='\t')) {
            server_teardown_index(i);
            return;
        }

        sendLine(chatFds[i], "server: unknown command (try hello/msg/listusr/whisper/quit)");
    }

    // Server initialization
    command void Application.setTestServer() {
        isServer = TRUE;
        serverFd = call Transport.socket();
        if(serverFd != NULL_SOCKET){
            socket_addr_t addr;
            addr.addr = TOS_NODE_ID;
            addr.port = 123;
            
            // Bind to port
            if(call Transport.bind(serverFd, &addr) == SUCCESS){
                // Start listening
                if(call Transport.listen(serverFd) == SUCCESS){
                    dbg(TRANSPORT_CHANNEL, "Node %u: Server listening on port %u\n", TOS_NODE_ID, addr.port);
                    // Start timer to check for connections
                    call Timer1.startPeriodic(500); // Check every 500ms
                }
            }
        }
    }
    
    // Client initialization
    command void Application.setTestClient(){
        isClient = TRUE;
        transferSize = 100;
        counter = 0; 
        clientState = 1;
        connect_attempts = 0;

        clientFd = call Transport.socket();
        if(clientFd != NULL_SOCKET){
            socket_addr_t localAddr, remoteAddr;
            
            localAddr.addr = TOS_NODE_ID;
            localAddr.port = 200;
            
            remoteAddr.addr = 1;
            remoteAddr.port = 123;
            
            // Bind to source port
            if(call Transport.bind(clientFd, &localAddr) == SUCCESS){
                // Connect to server
                if(call Transport.connect(clientFd, &remoteAddr) == SUCCESS){
                    dbg(TRANSPORT_CHANNEL, "Node %u: Client connecting to %u:%u\n", TOS_NODE_ID, 1, 123);
                    call Timer1.startPeriodic(500); // Start sending data every 500ms
                } else {
                    dbg(TRANSPORT_CHANNEL, "Node %u: Connect failed\n", TOS_NODE_ID);
                }
            } else {
                dbg(TRANSPORT_CHANNEL, "Node %u: Bind failed\n", TOS_NODE_ID);
            }
        } else {
            dbg(TRANSPORT_CHANNEL, "Node %u: Socket creation failed\n", TOS_NODE_ID);
        }
    }
    
    command void Application.setAppServer(){
        uint8_t i;
        chatServer = TRUE;
        chatClient = FALSE;
        chatN = 0;
        for(i = 0; i < CHAT_MAX_USERS; i++){
            users[i].used = FALSE;
            users[i].name[0] = 0;
            srvIn[i].w = srvIn[i].r = 0;
        }
        chatListenFd = call Transport.socket();
        if(chatListenFd != NULL_SOCKET){
            socket_addr_t addr;
            addr.addr = TOS_NODE_ID;
            addr.port = CHAT_SERVER_PORT;
            if(call Transport.bind(chatListenFd, &addr) == SUCCESS && call Transport.listen(chatListenFd) == SUCCESS){
                dbg(COMMAND_CHANNEL, "Node %u: Chat server listening on %u\n", TOS_NODE_ID, CHAT_SERVER_PORT);
                call Timer1.startPeriodic(100);
            }
            else{
                dbg(COMMAND_CHANNEL, "Node %u: Chat server bind/listen failed\n", TOS_NODE_ID);
            }
        }
    }

    command void Application.setAppClient(uint16_t port){
        chatClient = TRUE;
        chatServer = FALSE;
        chatCliFd = call Transport.socket();
        if(chatCliFd != NULL_SOCKET){
            socket_addr_t localAddr, remoteAddr;
            localAddr.addr = TOS_NODE_ID;
            localAddr.port = port;
            remoteAddr.addr = CHAT_SERVER_NODE;
            remoteAddr.port = CHAT_SERVER_PORT;
            if(call Transport.bind(chatCliFd, &localAddr) == SUCCESS && call Transport.connect(chatCliFd, &remoteAddr) == SUCCESS){
                dbg(COMMAND_CHANNEL, "Node %u: Chat client connecting to %u:%u\n", TOS_NODE_ID, CHAT_SERVER_NODE, CHAT_SERVER_PORT);
                call Timer1.startPeriodic(100);
            }
            else{
                dbg(COMMAND_CHANNEL, "Node %u: Chat client bind/connect failed\n", TOS_NODE_ID);
            }
        }
    }

    command void Application.appInject(uint8_t* line){
        // Only meaningful for the chat client; ignore otherwise
        if(chatClient && chatCliFd != NULL_SOCKET){
            // Send the exact line to server (appends CRLF)
            sendLine(chatCliFd, (const char*)line);

            // allow local meta-commands (e.g., to close immediately)
            if(strcmp((const char*)line, "quit") == 0){
                call Transport.close(chatCliFd);
            }
        }
    }

    // Timer for periodic operations
    event void Timer1.fired(){
        uint8_t i;
        uint16_t j;
        uint16_t bytesWritten;
        uint8_t buffer[128];
        uint16_t bytesRead;

        if(chatServer){
            // Accept new connections
            socket_t newFd = call Transport.accept(chatListenFd);
            if(newFd != NULL_SOCKET){
                bool already = FALSE;
                for(i = 0; i < chatN; i++){
                    if(chatFds[i] == newFd && users[i].used){
                        already = TRUE;
                        break;
                    }
                }
                if(!already && chatN < CHAT_MAX_USERS){
                    chatFds[chatN] = newFd;
                    srvIn[chatN].w = srvIn[chatN].r = 0;
                    users[chatN].used = TRUE;
                    users[chatN].name[0] = 0;
                    sendLine(newFd, " Welcome to the chat server!");
                    dbg(COMMAND_CHANNEL, "Node %u: Chat server accepted new connection, fd=%u\n", TOS_NODE_ID, newFd);
                    chatN++;
                }
                else if(!already){
                    dbg(COMMAND_CHANNEL, "Node %u: Chat server rejected connection, max users reached\n", TOS_NODE_ID);
                    sendLine(newFd, "Server full, try again later.");
                    call Transport.close(newFd);
                }
            }
            
            // Read from all connected clients
            for(i = 0; i < chatN; i++){
                uint8_t state = call Transport.getState(chatFds[i]);
                bytesRead = call Transport.read(chatFds[i], buffer, sizeof(buffer));
                if(bytesRead > 0){
                    char line[80];
                    ring_push(&srvIn[i], buffer, bytesRead);
                    while (ring_pop_line(&srvIn[i], line, sizeof(line))){
                        server_handle_line(i, line);
                    }
                }
                if(state == CLOSE_WAIT){
                    server_teardown_index(i);
                    i--; // adjust index after teardown
                    continue;
                }
            }
        }

        if(chatClient && chatCliFd != NULL_SOCKET){
            static uint8_t phase = 0; // 0=connecting, 1=hello sent, 2=reading, 3=closing, 4=done
            uint8_t state = call Transport.getState(chatCliFd);

            bytesRead = call Transport.read(chatCliFd, buffer, sizeof(buffer));
            if(bytesRead > 0){
                char line[64];
                ring_push(&cliIn, buffer, bytesRead);
                while(ring_pop_line(&cliIn, line, sizeof(line))){
                    dbg(COMMAND_CHANNEL, "Node %u: Chat client received: %s\n", TOS_NODE_ID, line);
                }
            }

            if(phase == 0 && state == ESTABLISHED){
                char nm[16];
                char hello[48];
                uint8_t p=0; 
                uint16_t id = TOS_NODE_ID;
                nm[p++]='u';

                if (id>=100) { 
                    nm[p++]='0'+(id/100)%10; 
                }
                if (id>=10)  { 
                    nm[p++]='0'+(id/10)%10;  
                }
                
                nm[p++]='0'+(id%10); 
                nm[p]=0;

                // hello <name> <port>
                snprintf(hello, sizeof(hello), "hello %s %u", nm, 200);
                sendLine(chatCliFd, hello);

                // send one sample message
                sendLine(chatCliFd, "msg hi-everyone");
                phase = 1;
            }

            if(phase == 1 || phase == 2){
                static uint8_t ticks = 0;
                bytesRead = call Transport.read(chatCliFd, buffer, sizeof(buffer));
                if(bytesRead > 0){
                    char line[64];
                    ring_push(&cliIn, buffer, bytesRead);
                    while(ring_pop_line(&cliIn, line, sizeof(line))){
                        dbg(COMMAND_CHANNEL, "Node %u: Chat client received: %s\n", TOS_NODE_ID, line);
                    }
                }
            }
            if(phase == 3 && state == CLOSED){
                dbg(COMMAND_CHANNEL, "Node %u: Chat client connection closed\n", TOS_NODE_ID);
                call Timer1.stop();
                phase = 4;
            }
        }

        if(isServer) {
            // Try to accept connections
            socket_t newFd = call Transport.accept(serverFd);
            if(newFd != NULL_SOCKET) {
                // Store accepted socket
                if(numAccepted < 5) {
                    uint8_t initialData[12];
                    uint16_t bytes;
                    acceptedSockets[numAccepted++] = newFd;
                    dbg(TRANSPORT_CHANNEL, "Node %u: Accepted connection socket %u\n", TOS_NODE_ID, newFd);
                    for(j = 0; j < 6; j++) { 
                        initialData[j*2] = (j >> 8) & 0xFF;
                        initialData[j*2 + 1] = j & 0xFF; 
                    }
                    bytes = call Transport.write(newFd, initialData, 12);
                    dbg(TRANSPORT_CHANNEL, "Node %u: Wrote %u initial bytes to accepted socket %u\n", TOS_NODE_ID, bytes, newFd);
                }
            }
            
            // Read from all accepted sockets
            for(i = 0; i < numAccepted; i++) {
                bytesRead = call Transport.read(acceptedSockets[i], buffer, sizeof(buffer));
                // dbg(TRANSPORT_CHANNEL, "Bytes read: %u\n", bytesRead);
                if(bytesRead > 0) {
                    dbg(TRANSPORT_CHANNEL, "Node %u: Reading Data:", TOS_NODE_ID);
                    for(j = 0; j < bytesRead; j+=2) {
                        value = ((uint16_t)buffer[j] << 8) | buffer[j + 1]; 
                        dbg_clear(TRANSPORT_CHANNEL, "%u,", value);
                    }
                    dbg_clear(TRANSPORT_CHANNEL, "\n");
                }
                else{
                    dbg(TRANSPORT_CHANNEL, "Nothing to read...\n");
                }
            }
        }
        else if(isClient && clientFd != NULL_SOCKET) {
            uint8_t state = call Transport.getState(clientFd);
            uint8_t bytesToSend;
            uint8_t sendBuffer[128];
            uint16_t startCounter;
            switch(clientState){
                case 1: // Connecting
                    connect_attempts++;
                    
                    if(state == ESTABLISHED){ 
                        dbg(TRANSPORT_CHANNEL, "Node %u: Connection established, starting transfer\n", TOS_NODE_ID);
                        clientState = 2;
                        counter = 0;
                    }
                    else if(connect_attempts > 200){ // timeout
                        dbg(TRANSPORT_CHANNEL, "Node %u: Connection timeout\n", TOS_NODE_ID);
                        call Timer1.stop();
                    } 
                    else{
                        dbg(TRANSPORT_CHANNEL, "Node %u: Waiting for connection... state=%u\n", TOS_NODE_ID, state);
                    }
                    break;

                case 2: // Sending
                    if(state != ESTABLISHED){
                        dbg(TRANSPORT_CHANNEL, "Node %u: Lost connection during transfer\n", TOS_NODE_ID);
                        clientState = 0;
                        call Timer1.stop();
                        break;
                    }
                    
                    startCounter = counter;
                    bytesToSend = 0;

                    while(counter < transferSize && bytesToSend < 128){
                        // Create 16-bit value
                        sendBuffer[bytesToSend++] = (counter >> 8) & 0xFF; // High byte
                        sendBuffer[bytesToSend++] = counter & 0xFF;        // Low byte
                        counter++;
                    }
                    
                    if(bytesToSend > 0){
                        bytesWritten = call Transport.write(clientFd, sendBuffer, bytesToSend);
                        if(bytesWritten > 0) {
                            dbg(TRANSPORT_CHANNEL, "Node %u: Sent %u bytes (values %u-%u)\n", 
                                TOS_NODE_ID, bytesWritten, counter - (bytesWritten/2), counter - 1);
                        } 
                        else{
                            dbg(TRANSPORT_CHANNEL, "Node %u: Write returned 0, will retry\n", TOS_NODE_ID);
                            counter = startCounter;
                        }
                    }
                    else{
                        dbg(TRANSPORT_CHANNEL, "Node %u: No data to send\n", TOS_NODE_ID);
                    }
                    
                    // Check if done
                    if(counter >= transferSize) {
                        dbg(TRANSPORT_CHANNEL, "Node %u: Finished sending %u bytes, closing\n", 
                            TOS_NODE_ID, transferSize * 2);
                        clientState = 3;
                        call Transport.close(clientFd);
                    }

                    if(state == CLOSE_WAIT){
                        call Transport.close(clientFd);
                    }
                    break;
                case 3: // Closing
                    if(state == CLOSED) {
                        dbg(TRANSPORT_CHANNEL, "Node %u: Connection closed\n", TOS_NODE_ID);
                        call Timer1.stop();
                        clientState = 0;
                    }
                    break;
                }
            }
        }
    }
