#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendinfo.h"
#include "../../includes/channels.h"

interface Flooding {
    command void start();
    command void floodNeighbors(uint16_t destinaiton, uint8_t *payload);
    command void handleFlood(uint16_t protocol, uint16_t src, uint16_t seq, uint16_t TTL, uint16_t destionation, uint8_t *msgContent);
}