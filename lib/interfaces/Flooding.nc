#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/flooding.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendinfo.h"
#include "../../includes/channels.h"

interface Flooding {
    command void start();
    command void floodLSA(uint8_t* lsaPayload, uint8_t len);
    command bool isReady();
    command void forwardLSA(flood_header* floodHdr, uint16_t receivedFrom, uint8_t* lsaPayload);
    command void sendLSAACK(uint16_t neighbor, uint16_t seq);
    event void receivedLSA(uint16_t src, uint8_t* lsaData);
}