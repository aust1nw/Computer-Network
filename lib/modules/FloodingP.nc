#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/flooding.h"
#include "../../includes/LSA.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendinfo.h"
#include "../../includes/channels.h"
#include "../../includes/neighborEntry.h"

generic module FloodingP(){
    provides interface Flooding;
    
    uses interface Timer<TMilli> as FloodingTimer;
    uses interface Random;

    uses interface Packet;
    uses interface Receive as FloodReceive;
    
    uses interface Hashmap<NeighborEntry> as NeighborTable;

    uses interface SimpleSend as Send;
    uses interface NeighborDiscovery;
}

implementation{
    uint16_t mySeqNum = 1;
    uint8_t lastCount = 0;
    uint8_t stableCount = 0;
    bool ready = FALSE;

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t *payload, uint8_t length){
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;

        if(payload != NULL && length > 0){
            memcpy(Package->payload, payload, length);
        }
    }
    
    void makeFloodHeader(flood_header *header, uint16_t src, uint16_t seq, uint16_t TTL){
        header->src = src;
        header->seq = seq;
        header->TTL = TTL;
    }

    bool hasCache(uint16_t nodeID, uint16_t seq){
        NeighborEntry entry;
        uint8_t i;
        if(!call NeighborTable.contains(nodeID)){
            return FALSE;
        }
        entry = call NeighborTable.get(nodeID);
        for(i = 0; i < entry.count; i++){
            if(entry.seq[i] == seq){
                return TRUE;
            }
        }
        return FALSE;
    }
    
    void updCount1(uint8_t* count){
        (*count)++;
    }

    void updCount2(uint8_t* count1, uint8_t count2){
        *count1 = count2;
    }
    
    void updSeq1(uint16_t* seq){
        (*seq)++;
    }

    NeighborEntry updEntry(uint16_t entry, uint16_t seq, uint16_t protocol){
        NeighborEntry editEntry;
        uint8_t it;

        if(call NeighborTable.contains(entry)){
            editEntry = call NeighborTable.get(entry);
        }
        else{
            editEntry.count = 0;
        }
        
        it = editEntry.count % 10;
        editEntry.seq[it] = seq;

        if(editEntry.count < 10){
            editEntry.count++;
        }
        

        return editEntry;
    }

    command void Flooding.start(){
        call FloodingTimer.startPeriodic(2000 + (uint16_t)(call Random.rand16()%1000));
    }

    command void Flooding.floodLSA(uint8_t* lsaPayload, uint8_t len){
        pack linkPacket;
        flood_header floodHdr;
        uint8_t combinedPayload[PACKET_MAX_PAYLOAD_SIZE];
        uint16_t* neighbors;
        uint8_t numNeighbors;
        uint8_t i;
        
        numNeighbors = call NeighborDiscovery.getCount();
        neighbors = call NeighborDiscovery.getNeighborList();

        if(numNeighbors == 0){
            dbg(FLOODING_CHANNEL, "Node %u: No neighbors to flood LSA\n", TOS_NODE_ID);
            return;
        }

        makeFloodHeader(&floodHdr, TOS_NODE_ID, mySeqNum, MAX_TTL);
        
        // Payload: [flood_header][LSA data]
        memcpy(combinedPayload, &floodHdr, FLOODING_HEADER_LENGTH);
        memcpy(combinedPayload + FLOODING_HEADER_LENGTH, lsaPayload, len);

        dbg(FLOODING_CHANNEL, "Node %u: Flooding LSA seq %u to %u neighbors\n", TOS_NODE_ID, mySeqNum, numNeighbors);

        for(i = 0; i < numNeighbors; i++){
            makePack(&linkPacket, TOS_NODE_ID, neighbors[i], MAX_TTL, PROTOCOL_FLOODING, 0, combinedPayload, PACKET_MAX_PAYLOAD_SIZE);
            call Send.send(linkPacket, neighbors[i]);
            call NeighborTable.insert(neighbors[i], updEntry(neighbors[i], mySeqNum, PROTOCOL_FLOODING));
            dbg(FLOODING_CHANNEL, "  -> Sent LSA to neighbor %u\n", neighbors[i]);
        }

        updSeq1(&mySeqNum);
    }

    event void FloodingTimer.fired(){
        uint8_t numNeighbors = call NeighborDiscovery.getCount();
        uint8_t i;

        for(i = 0; i < numNeighbors; i++){
            uint32_t neighbor = call NeighborDiscovery.getList(i);
            if(!call NeighborTable.contains(neighbor)){
                NeighborEntry newEntry;
                newEntry.count = 0;
                call NeighborTable.insert(neighbor, newEntry);
                dbg(FLOODING_CHANNEL, "Node %u: Added neighbor %u to table\n", TOS_NODE_ID, neighbor);
            }
        }

        if(numNeighbors > 0 && !ready){
            ready = TRUE;
            dbg(FLOODING_CHANNEL, "Node %u: Flooding module is ready\n", TOS_NODE_ID);
        }

        updCount2(&lastCount, numNeighbors);
        
    }

    command bool Flooding.isReady(){
        return ready;
    }

    event message_t* FloodReceive.receive(message_t* msg, void* payload, uint8_t len){
        if(len==sizeof(pack)){
            pack* linkPkt=(pack*) payload;
            
            // Handle LSA flooding packets
            if(linkPkt->protocol == PROTOCOL_FLOODING){
                flood_header* floodHdr = (flood_header*)linkPkt->payload;
                uint8_t* lsaPayload = (uint8_t*)(linkPkt->payload + FLOODING_HEADER_LENGTH);
                
                // dbg(FLOODING_CHANNEL, "Node %u: Received LSA from %u (seq %u)\n", TOS_NODE_ID, floodHdr->src, floodHdr->seq);
                
                if (hasCache(floodHdr->src, floodHdr->seq)) {
                    call Flooding.sendLSAACK(linkPkt->src, floodHdr->seq);
                }

                call NeighborTable.insert(floodHdr->src, updEntry(floodHdr->src, floodHdr->seq, PROTOCOL_FLOODING));

                call Flooding.sendLSAACK(linkPkt->src, floodHdr->seq);
                
                // Forward the LSA to other neighbors
                call Flooding.forwardLSA(floodHdr, linkPkt->src, lsaPayload);
                // dbg(GENERAL_CHANNEL, "Forwarding LSA\n");
                
                // Notify LSRouting to process this LSA
                signal Flooding.receivedLSA(floodHdr->src, lsaPayload);
                // dbg(ROUTING_CHANNEL, "Node %u: Signaled received LSA from %u to LSRouting\n", TOS_NODE_ID, floodHdr->src);
            }
            else if(linkPkt->protocol == PROTOCOL_LSA_ACK){
                call NeighborTable.insert(linkPkt->src, updEntry(linkPkt->src, linkPkt->seq, PROTOCOL_LSA_ACK));
                dbg(FLOODING_CHANNEL, "Node %u: Received LSA ACK from %u\n", TOS_NODE_ID, linkPkt->src);
            }
            return msg;
        }
        return msg;
    }

    command void Flooding.sendLSAACK(uint16_t neighbor, uint16_t seq){
        pack ackPacket;
        uint8_t *payload = 0;
        
        dbg(FLOODING_CHANNEL, "Node %u: Sending LSA ACK to %u for seq %u\n", TOS_NODE_ID, neighbor, seq);
            
        makePack(&ackPacket, TOS_NODE_ID, neighbor, 1, PROTOCOL_LSA_ACK, seq, payload, 0);
        call Send.send(ackPacket, neighbor);
        call NeighborTable.insert(neighbor, updEntry(neighbor, seq, PROTOCOL_LSA_ACK));
    }

    command void Flooding.forwardLSA(flood_header* floodHdr, uint16_t receivedFrom, uint8_t* lsaPayload){
        pack floodPack;
        flood_header newFloodHdr;
        uint8_t combinedPayload[PACKET_MAX_PAYLOAD_SIZE];
        uint16_t* neighbors;
        uint8_t numNeighbors;
        uint8_t i;
        
        // Check TTL
        if(floodHdr->TTL == 0){
            dbg(FLOODING_CHANNEL, "LSA TTL expired, not forwarding\n");
            return;
        }
        
        // Decrement TTL
        makeFloodHeader(&newFloodHdr, floodHdr->src, floodHdr->seq, floodHdr->TTL - 1);
        
        // Rebuild payload
        memcpy(combinedPayload, &newFloodHdr, FLOODING_HEADER_LENGTH);
        memcpy(combinedPayload + FLOODING_HEADER_LENGTH, lsaPayload, sizeof(LSA));
        
        numNeighbors = call NeighborDiscovery.getCount();
        neighbors = call NeighborDiscovery.getNeighborList();
        
        dbg(FLOODING_CHANNEL, "Forwarding LSA to other neighbors\n");
        
        // Forward to all neighbors except sender
        for(i = 0; i < numNeighbors; i++){
            if(neighbors[i] == receivedFrom) continue;
                
            makePack(&floodPack, TOS_NODE_ID, neighbors[i], MAX_TTL, PROTOCOL_FLOODING, 0, combinedPayload, PACKET_MAX_PAYLOAD_SIZE);
            call Send.send(floodPack, neighbors[i]);
            call NeighborTable.insert(neighbors[i], updEntry(neighbors[i], floodHdr->seq, PROTOCOL_FLOODING));
            dbg(FLOODING_CHANNEL, "Forwarded LSA to neighbor %u\n", neighbors[i]);
        }
    }
    
    event void NeighborDiscovery.neighborsChanged(){
        uint8_t numNeighbors = call NeighborDiscovery.getCount();
        uint32_t *keys = call NeighborTable.getKeys();
        uint16_t tableSize = call NeighborTable.size();
        uint8_t i;

        dbg(FLOODING_CHANNEL, "Node %u: Neighbor list changed\n", TOS_NODE_ID);
        
        for(i = 0; i < numNeighbors; i++){
            uint32_t neighbor = call NeighborDiscovery.getList(i);
            if(!call NeighborTable.contains(neighbor)){
                NeighborEntry newEntry;
                newEntry.count = 0;
                call NeighborTable.insert(neighbor, newEntry);
            }
        }
        
        for(i = 0; i < tableSize; i++){
            uint16_t tableNeighbor = (uint16_t)keys[i];
            bool stillNeighbor = FALSE;
            uint8_t j;
            for(j = 0; j < numNeighbors; j++){
                if(call NeighborDiscovery.getList(j) == tableNeighbor){
                    stillNeighbor = TRUE;
                    break;
                }
            }
            if(!stillNeighbor){
                call NeighborTable.remove(tableNeighbor);
                dbg(FLOODING_CHANNEL, "Removed old neighbor %u from table\n", tableNeighbor);
            }
        }
    }
}