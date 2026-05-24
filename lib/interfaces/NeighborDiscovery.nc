#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendinfo.h"
#include "../../includes/channels.h"

interface NeighborDiscovery{
    command void start();
    command void printNeighbors();
    command void receiveNeighbors(uint16_t protocol, uint16_t src, uint8_t* idx);
    command uint8_t getCount();
    command uint32_t getList(uint8_t count);

    command uint16_t getLinkCost(uint16_t neighborId);
    
    command uint16_t* getNeighborList();
    command uint32_t* getCostList();
    
    event void neighborsChanged();

    command bool isNeighbor(uint16_t neighborId);
}