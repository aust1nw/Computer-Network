#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendinfo.h"
#include "../../includes/channels.h"

generic module FloodingP(){
    provides interface Flooding;
    
    uses interface Timer<TMilli> as FloodingTimer;
    uses interface Random;

    uses interface SimpleSend as Send;
    uses interface NeighborDiscovery as Discover;

    uses interface Packet;
    uses interface Hashmap<uint16_t> as NeighborTable;
}

implementation{
    uint16_t seqNum = 0;
    pack sendPacket;
    pack returnPacket;

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t *payload, uint8_t length);
    
    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t *payload, uint8_t length){
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
    }

    bool hasCache(uint16_t nodeID, uint16_t seq){
        // check NeighborTable with nodeID key, if has value seqNum
        if(call NeighborTable.contains(nodeID)){
            uint16_t lastSeq = call NeighborTable.get(nodeID);
            if(lastSeq == seq){
                return TRUE;
            }
        }
        return FALSE;
    }

    command void Flooding.start(){
        uint8_t i;
        uint8_t count = call Discover.getCount();

        for(i = 0; i < count; i++){
            uint32_t neighbor = call Discover.getList(i);
            call NeighborTable.insert(neighbor, -1);
        }

        call FloodingTimer.startOneShot(1000 + (uint16_t)(call Random.rand16()%1000));
    }

    task void floodNeighbors(){
        uint8_t *payload = 0;
        uint16_t SEND = 0;
        uint16_t source = TOS_NODE_ID;
        uint16_t destination = AM_BROADCAST_ADDR;
        // check if destination has cache by checking NeighborTable if the node has the seqNum already
        if(hasCache(destination, seqNum)){
            return;
        }
        else{
            makePack(&sendPacket, source, destination, 15, SEND, seqNum, payload, PACKET_MAX_PAYLOAD_SIZE);
            call Send.send(sendPacket, destination);
        }

        seqNum += 1;
    }

    event void FloodingTimer.fired(){
        post floodNeighbors();
    }

    command void Flooding.printNeighbors(){
        // not sure if needed
    }

    command void Flooding.handleFlood(pack* Package, uint16_t protocol, uint16_t src, uint16_t seq, uint16_t TTL, uint8_t *msgContent){
        // will be connected through Node.nc
        uint16_t RECEIVED = 1;
        uint8_t *payload = 0;
        if(protocol == 1){
            // update NeighborTable cache for neighbors
            call NeighborTable.insert(src, seq);
        }
        else if(protocol == 0){
            // update NeighborTable cache for source node
            if(hasCache(AM_BROADCAST_ADDR, seq) || TTL == 0){
                return;
            }
            else{
                uint16_t newTTL = TTL - 1;
                makePack(Package, src, AM_BROADCAST_ADDR, newTTL, protocol, seq, msgContent, PACKET_MAX_PAYLOAD_SIZE);
                call Send.send(*Package, AM_BROADCAST_ADDR);
            }
            makePack(&returnPacket, TOS_NODE_ID, src, 0, RECEIVED, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
            call Send.send(returnPacket, src);
            call NeighborTable.insert(src, seq);
        }
    }

    command void Flooding.checkStatus(){
        // after a certain statistic, check if node is active
        // if not, then mark not active
        // make it so also check status before sending
        // if inactive->don't send, else if active->send
    }
}