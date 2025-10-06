#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendinfo.h"
#include "../../includes/channels.h"
#include "../../includes/neighborEntry.h"

generic module FloodingP(){
    provides interface Flooding;
    
    uses interface Timer<TMilli> as FloodingTimer1;
    // uses interface Timer<TMilli> as FloodingTimer2;
    uses interface Random;

    uses interface Packet;
    // uses interface Receive as FloodReceive;
    
    uses interface Hashmap<NeighborEntry> as NeighborTable;

    uses interface SimpleSend as Send;
    uses interface NeighborDiscovery;
}

implementation{
    uint16_t seqNum = 1;
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

    bool isActive(uint16_t nodeID){
        NeighborEntry statEntry;

        if(!call NeighborTable.contains(nodeID)){
            return FALSE;
        }

        statEntry = call NeighborTable.get(nodeID);

        if(statEntry.numReceived > 5 && statEntry.average <= 70){
            return FALSE;
        }

        return TRUE;
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
    void updSeq2(uint16_t* curSeq, uint16_t prevSeq){
        *curSeq = prevSeq;
    }

    NeighborEntry updEntry(uint16_t entry, uint16_t seq, uint16_t protocol){
        NeighborEntry editEntry;
        uint8_t it;

        if(call NeighborTable.contains(entry)){
            editEntry = call NeighborTable.get(entry);
        }
        else{
            editEntry.count = 0;
            editEntry.numReceived = 0;
            editEntry.numReplied = 0;
            editEntry.average = 100;
        }
        
        it = editEntry.count % 10;
        editEntry.seq[it] = seq;

        if(editEntry.count < 10){
            editEntry.count++;
        }
        if(protocol == PROTOCOL_PING){
            editEntry.numReceived++;
        }
        else if(protocol == PROTOCOL_PINGREPLY){
            editEntry.numReplied++;
        }
        else{
            dbg(FLOODING_CHANNEL, "Invalid protocol\n");
        }
        if(editEntry.numReceived > 0){
            editEntry.average = (100*editEntry.numReplied)/editEntry.numReceived;
        } 
        else{
            editEntry.average = 0;
        }

        return editEntry;
    }

    command void Flooding.start(){
        call FloodingTimer1.startPeriodic(1000 + (uint16_t)(call Random.rand16()%1000));
    }

    command void Flooding.floodNeighbors(uint16_t destination, uint8_t *payload){
        pack sendPacket;
        uint16_t source = TOS_NODE_ID;
        uint32_t *keys = call NeighborTable.getKeys();
        uint16_t count = call NeighborTable.size();
        uint8_t i;

        // dbg(FLOODING_CHANNEL, "Node %u preparing to flood seq %u to %u neighbors\n", TOS_NODE_ID, seqNum, count);

        for(i = 0; i < count; i++){
            uint16_t neighbor = (uint16_t)keys[i];
            if(!hasCache(neighbor, seqNum) && isActive(neighbor)){
                makePack(&sendPacket, source, destination, MAX_TTL, PROTOCOL_PING, seqNum, payload, PACKET_MAX_PAYLOAD_SIZE);
                call Send.send(sendPacket, neighbor);
                call NeighborTable.insert(neighbor, updEntry(neighbor, seqNum, PROTOCOL_PING));
                dbg(FLOODING_CHANNEL, "%u has flooded to %u with seq %u\n", TOS_NODE_ID, neighbor, seqNum);
            }
            else{
                dbg(FLOODING_CHANNEL, "Skipped flooding for %u; already has seq %u\n", neighbor, seqNum);
            }
        }

        updSeq1(&seqNum);

        // call FloodingTimer2.startPeriodic(1000 + (uint16_t)(call Random.rand16()%1000));
    }

    event void FloodingTimer1.fired(){
        uint8_t numNeighbors = call NeighborDiscovery.getCount();
        uint8_t i;
        if(lastCount == numNeighbors){
            updCount1(&stableCount);
        }
        if(stableCount >= 2){
            for(i = 0; i < numNeighbors; i++){
                uint32_t neighbor = call NeighborDiscovery.getList(i);
                if(!call NeighborTable.contains(neighbor)){
                    NeighborEntry newEntry;
                    newEntry.count = 0;
                    newEntry.numReceived = 0;
                    newEntry.numReplied = 0;
                    newEntry.average = 100;
                    call NeighborTable.insert(neighbor, newEntry);
                    // dbg(FLOODING_CHANNEL, "Inserted %u into the table\n", neighbor);
                }
            }
            ready = TRUE;
            // dbg(FLOODING_CHANNEL, "Ready to Flood\n");
            // post floodNeighbors();
            return;
        }
        else{
            updCount2(&lastCount, numNeighbors);
        }
    }

    // event void FloodingTimer2.fired(){
    //     post floodNeighbors();
    // }

    // event message_t* FloodReceive.receive(message_t* msg, void* payload, uint8_t len){
    //     if(len==sizeof(pack)){
    //         pack* myMsg=(pack*) payload;
    //         call Flooding.handleFlood(myMsg->protocol, myMsg->src, myMsg->seq, myMsg->TTL, payload);
    //         return msg;
    //     }
    //     return msg;
    // }

    command void Flooding.handleFlood(uint16_t protocol, uint16_t src, uint16_t seq, uint16_t TTL, uint16_t destination, uint8_t *msgContent){
        pack returnPacket;
        pack floodPack;
        uint8_t *payload = 0;
        uint32_t *keys = call NeighborTable.getKeys();
        uint16_t count = call NeighborTable.size();
        uint16_t returnTTL = 1;
        uint16_t returnSeq = seq;
        uint8_t i;
        
        if(protocol == PROTOCOL_PINGREPLY){
            call NeighborTable.insert(src, updEntry(src, seq, protocol));
            dbg(FLOODING_CHANNEL, "%u received a reply from %u\n", TOS_NODE_ID, src);
        }
        else if(protocol == PROTOCOL_PING){
            call NeighborTable.insert(src, updEntry(src, seq, PROTOCOL_PINGREPLY));
            makePack(&returnPacket, TOS_NODE_ID, src, returnTTL, PROTOCOL_PINGREPLY, returnSeq, payload, PACKET_MAX_PAYLOAD_SIZE);
            call Send.send(returnPacket, src);
            dbg(FLOODING_CHANNEL, "%u has replied to %u\n", TOS_NODE_ID, src);
            if(seq >= seqNum){
                updSeq2(&seqNum, seq);
                updSeq1(&seqNum);
            }
            if(TOS_NODE_ID == destination){
                dbg(FLOODING_CHANNEL, "Success\n");
                return;
            }
            for(i = 0; i < count; i++){
                uint16_t neighbor = (uint16_t)keys[i];
                
                if (neighbor == src) continue;

                if(!hasCache(neighbor, seq) && TTL > 0 && isActive(neighbor)){
                    uint16_t newTTL = TTL - 1;
                    call NeighborTable.insert(neighbor, updEntry(neighbor, seq, protocol));
                    makePack(&floodPack, TOS_NODE_ID, destination, newTTL, protocol, seq, msgContent, PACKET_MAX_PAYLOAD_SIZE);
                    call Send.send(floodPack, neighbor);
                    dbg(FLOODING_CHANNEL, "%u has flooded to %u with seq %u\n", TOS_NODE_ID, neighbor, seq);
                }
                else{
                    dbg(FLOODING_CHANNEL, "Skipped flooding to %u; already has seq %u or is inactive.\n", neighbor, seq);
                    dbg(FLOODING_CHANNEL, "Destination %u active status: %s\n", neighbor, isActive(neighbor) ? "ACTIVE" : "INACTIVE");
                }
            }
        }
        else{
            // dbg(FLOODING_CHANNEL, "Unknown protocol\n");
            return;
        }
    }
}