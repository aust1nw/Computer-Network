#ifndef ROUTE_ENTRY_H
#define ROUTE_ENTRY_H

typedef struct{
    uint16_t dest;    

    uint16_t primaryNextHop;
    uint16_t primaryCost;

    uint16_t backup1NextHop;
    uint16_t backup1Cost;

    uint16_t backup2NextHop;
    uint16_t backup2Cost;

    uint8_t routeCount;       
} route_entry;

#endif