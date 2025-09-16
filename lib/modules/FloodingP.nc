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

    uses interface Packet;
}

implementation{
    uint16_t seqNum = 0;
    pack sendPackage;
    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t *payload, uint8_t length);

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t *payload, uint8_t length){
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
    }

    command void Flooding.start(){
        call FloodingTimer.startOneShot(1000 + (uint16_t)(call Random.rand16()%1000));
    }

    task void floodNeighbors(){

    }

    event void FloodingTimer.fired(){
        post floodNeighbors();
    }

    command void Flooding.printNeighbors(){

    }

    command voild Flooding.checkStatus(){

    }
}