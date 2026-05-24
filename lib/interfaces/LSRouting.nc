#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/LSA.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendinfo.h"
#include "../../includes/channels.h"

interface LSRouting{
    // Initialize LS routing
    command void start();
    
    // Query routing table
    command uint16_t getCost(uint16_t dest);
    command uint16_t getRouteCost(uint16_t dest, uint8_t routeIndex);
    command uint16_t getBestNextHop(uint16_t dest);
    
    command void printRouteTable();
}