#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendinfo.h"
#include "../../includes/channels.h"

interface NeighborDiscovery{
    command void start();
    command void printNeighbors();
    command void receiveNeighbors(uint16_t packet, uint16_t src);
}