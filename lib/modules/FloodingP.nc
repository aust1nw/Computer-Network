#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendinfo.h"
#include "../../includes/channels.h"
#include "../../includes/neighborEntry.h"

generic module FloodingP(){
    provides interface Flooding;
    
    uses interface Timer<TMilli> as FloodingTimer;
    uses interface Random;

    uses interface Packet;
    uses interface Hashmap<NeighborEntry> as NeighborTable;

    uses interface SimpleSend as Send;
    uses interface NeighborDiscovery;
}

implementation{
    uint16_t seqNum = 1;

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

    void updSeq(uint16_t *seq){
        (*seq)++;
    }

    NeighborEntry updCache(uint16_t src, uint16_t seq){
        NeighborEntry editEntry;
        uint8_t it;
        
        if(call NeighborTable.contains(src)){
            editEntry = call NeighborTable.get(src);
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
        call FloodingTimer.startOneShot(1000 + (uint16_t)(call Random.rand16()%1000));
    }

    task void floodNeighbors(){
        pack sendPacket;
        uint8_t *payload = 0;
        uint16_t SEND = 0;
        uint16_t source = TOS_NODE_ID;
        uint32_t *keys = call NeighborTable.getKeys();
        uint16_t count = call NeighborTable.size();
        uint8_t i;

        dbg(FLOODING_CHANNEL, "Node %u preparing to flood seq %u to %u neighbors\n", TOS_NODE_ID, seqNum, count);

        for(i = 0; i < count; i++){
            uint16_t destination = (uint16_t)keys[i];
            if(!hasCache(destination, seqNum)){
                makePack(&sendPacket, source, destination, MAX_TTL, SEND, seqNum, payload, PACKET_MAX_PAYLOAD_SIZE);
                call Send.send(sendPacket, destination);
                dbg(FLOODING_CHANNEL, "%u has flooded to %u\n", TOS_NODE_ID, destination);
            }
            else{
                dbg(FLOODING_CHANNEL, "Skipped flooding to %u: already has seq %u\n", destination, seqNum);
            }
        }

        updSeq(&seqNum);

        call FloodingTimer.startPeriodic(1000 + (uint16_t)(call Random.rand16()%1000));
    }

    event void FloodingTimer.fired(){
        uint8_t numNeighbors = call NeighborDiscovery.getCount();
        uint8_t i;
        if(numNeighbors > 0){
            for(i = 0; i < numNeighbors; i++){
                uint32_t neighbor = call NeighborDiscovery.getList(i);
                if(!call NeighborTable.contains(neighbor)){
                    NeighborEntry newEntry;
                    newEntry.count = 0;
                    call NeighborTable.insert(neighbor, newEntry);
                    dbg(FLOODING_CHANNEL, "Inserted neighbor %u into the table\n", neighbor);
                }
            }
            dbg(FLOODING_CHANNEL, "Ready to Flood\n");
            post floodNeighbors();
        }
        else{
            call FloodingTimer.startOneShot(1000 + (uint16_t)(call Random.rand16()%1000));
        }
    }

    command void Flooding.handleFlood(uint16_t protocol, uint16_t src, uint16_t seq, uint16_t TTL, uint8_t *msgContent){
        NeighborEntry entry;
        pack returnPacket;
        pack floodPack;
        uint16_t RECEIVED = 1;
        uint8_t *payload = 0;
        uint32_t *keys = call NeighborTable.getKeys();
        uint16_t count = call NeighborTable.size();
        uint16_t returnTTL = 1;
        uint16_t returnSeq = 0;
        uint8_t i;
        if(protocol == 1){
            call NeighborTable.insert(src, updCache(src, seq));
            dbg(FLOODING_CHANNEL, "%u received a reply from %u\n", TOS_NODE_ID, src);
        }
        else if(protocol == 0){
            call NeighborTable.insert(src, updCache(src, seq));
            makePack(&returnPacket, TOS_NODE_ID, src, returnTTL, RECEIVED, returnSeq, payload, PACKET_MAX_PAYLOAD_SIZE);
            call Send.send(returnPacket, src);
            dbg(FLOODING_CHANNEL, "%u has replied to %u\n", TOS_NODE_ID, src);
            // check neighborCache and TTL before flooding some more
            for(i = 0; i < count; i++){
                uint16_t destination = (uint16_t)keys[i];
                if(!hasCache(destination, seq) && TTL > 0){
                    uint16_t newTTL = TTL - 1;
                    makePack(&floodPack, TOS_NODE_ID, destination, newTTL, protocol, seq, msgContent, PACKET_MAX_PAYLOAD_SIZE);
                    call Send.send(floodPack, destination);
                    dbg(FLOODING_CHANNEL, "%u has flooded to %u with seq: %u\n", TOS_NODE_ID, destination, seq);
                }
            }
             
        }
    }

    command void Flooding.checkStatus(){
        // after a certain statistic, check if node is active
        // if not, then mark not active
        // make it so also check status before sending
        // if inactive->don't send, else if active->send
    }
}