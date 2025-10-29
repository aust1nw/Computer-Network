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
    
    // Generate and flood this node's LSA
    command void sendLSA();
    
    // Process received LSA
    command void handleLSA(uint16_t src, uint8_t* lsaData);
    
    // Run Dijkstra and update routing table
    command void computeRoutes();
    
    // Query routing table
    command uint16_t getCost(uint16_t dest);
    command uint16_t getRouteCost(uint16_t dest, uint8_t routeIndex);
    command uint16_t getBestNextHop(uint16_t dest);
    command uint16_t routeFailed(uint16_t dest, uint16_t failedNextHop);
    command uint8_t getRouteCount(uint16_t dest);
    
    command void printRouteTable();

    command void printLinkState();
}