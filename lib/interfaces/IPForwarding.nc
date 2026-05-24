#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendinfo.h"
#include "../../includes/channels.h"

interface IPForwarding {
    command void start();
    command error_t sendPing(uint16_t dest, uint8_t* payload, uint8_t len);
    command error_t sendTCP(uint16_t dest, uint8_t* payload, uint8_t len);
    event void packReachedDest(pack* linkPkt, uint8_t len);
}