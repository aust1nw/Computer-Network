#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendinfo.h"
#include "../../includes/channels.h"

interface Flooding {
    command void start();
    command void flood(uint16_t* payload, uint16_t length);
    command void printNeighbors();
    command void checkStatus();
}