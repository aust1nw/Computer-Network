#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendinfo.h"
#include "../../includes/channels.h"

interface NeighborDiscovery{
    command void start();
    command void printNeighbors();
    command void receiveNeighbors(uint16_t protocol, uint16_t src, uint8_t *idx);
    command uint8_t getCount();
    command uint32_t getList(uint8_t count);
}