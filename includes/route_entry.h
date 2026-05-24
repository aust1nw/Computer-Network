#ifndef ROUTE_ENTRY_H
#define ROUTE_ENTRY_H

typedef struct{
    uint16_t dest;    

    uint16_t primaryNextHop;
    uint16_t primaryCost;
      
} route_entry;

#endif