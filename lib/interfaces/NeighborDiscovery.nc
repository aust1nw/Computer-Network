#include "../../includes/packet.h"

interface NeighborDiscovery(
    command void start();
    command void printNeighbors();
    command void receiveNeighbors(uint16_t packet, uint16_t src);
)