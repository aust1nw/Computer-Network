#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendinfo.h"
#include "../../includes/channels.h"

interface Flooding {
    command void start();
    command void printNeighbors();
    command void handleFlood(pack* Package, uint16_t protocol, uint16_t src, uint16_t seq, uint16_t TTL, uint8_t *msgContent);
    command void checkStatus();
}