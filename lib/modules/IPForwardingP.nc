#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/ip_header.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendinfo.h"
#include "../../includes/channels.h"

generic module IPForwardingP(){
    provides interface IPForwarding;
    
    uses interface LSRouting;
    uses interface Packet;
    uses interface Receive as IPReceive;
    uses interface SimpleSend as Send;
}

implementation{
    bool initialized = FALSE;

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t *payload, uint8_t length){
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;

        if(payload != NULL && length > 0){
            memcpy(Package->payload, payload, length);
        }
    }

    void makeIPHeader(ip_header *header, uint16_t src, uint16_t dest, uint8_t TTL, uint8_t protocol){
        header->src = src;
        header->dest = dest;
        header->TTL = TTL;
        header->protocol = protocol;
    }

    command void IPForwarding.start(){
        initialized = TRUE;
        dbg(GENERAL_CHANNEL, "Node %u: IP Forwarding initialized\n", TOS_NODE_ID);
    }

    command error_t IPForwarding.sendPing(uint16_t dest, uint8_t* payload, uint8_t len){
        pack ipPacket;
        ip_header ipHdr;
        uint8_t combinedPayload[PACKET_MAX_PAYLOAD_SIZE];
        uint16_t nextHop;
        uint8_t effective_len = len;

        if(!initialized){
            dbg(GENERAL_CHANNEL, "Node %u: IP not initialized\n", TOS_NODE_ID);
            return FAIL;
        }

        if(dest == 0 || dest == TOS_NODE_ID){
            dbg(GENERAL_CHANNEL, "Node %u: Invalid destination\n", TOS_NODE_ID);
            return FAIL;
        }

        nextHop = call LSRouting.getBestNextHop(dest);
        dbg(GENERAL_CHANNEL, "Node %u: Sending ping - final dest=%u, got nextHop=%u\n", TOS_NODE_ID, dest, nextHop);

        if(nextHop == 0){
            dbg(GENERAL_CHANNEL, "Node %u: No route to dest %u\n", TOS_NODE_ID, dest);
            return FAIL;
        }

        makeIPHeader(&ipHdr, TOS_NODE_ID, dest, DEFAULT_TTL, PROTOCOL_PING);

        if(IP_HEADER_LENGTH + len > PACKET_MAX_PAYLOAD_SIZE){
            effective_len = PACKET_MAX_PAYLOAD_SIZE - IP_HEADER_LENGTH;
        }

        // Combine IP header + payload
        memcpy(combinedPayload, (uint8_t*)&ipHdr, IP_HEADER_LENGTH);
        if(payload != NULL && effective_len > 0){
            memcpy(combinedPayload + IP_HEADER_LENGTH, payload, effective_len);
        }
        // Create link-layer packet
        makePack(&ipPacket, TOS_NODE_ID, nextHop, MAX_TTL, PROTOCOL_IP, 0, combinedPayload, IP_HEADER_LENGTH + effective_len);

        dbg(GENERAL_CHANNEL, "Node %u: Sending ping to %u via next hop %u\n", TOS_NODE_ID, dest, nextHop);
        
        dbg(GENERAL_CHANNEL, "Sending to %u\n", nextHop);
        call Send.send(ipPacket, nextHop);

        return SUCCESS;
    }
    
    error_t forwardPacket(pack* originalPkt, ip_header* ipHdr, uint8_t* payload, uint8_t len){
        pack forwardPack;
        ip_header modifiedHdr;
        uint16_t nextHop;
        uint8_t combinedPayload[PACKET_MAX_PAYLOAD_SIZE];
        
        dbg(GENERAL_CHANNEL, "Node %u: Forwarding packet src=%u dest=%u\n", TOS_NODE_ID, ipHdr->src, ipHdr->dest);

        // Create modified IP header in network byte order
        modifiedHdr.src = ipHdr->src;      
        modifiedHdr.dest = ipHdr->dest;    
        modifiedHdr.protocol = ipHdr->protocol;
        
        // Check and decrement IP TTL
        if(ipHdr->TTL <= 1){
            dbg(GENERAL_CHANNEL, "Node %u: IP TTL expired\n", TOS_NODE_ID);
            return FAIL;
        }
        modifiedHdr.TTL = ipHdr->TTL - 1;
        
        // Get next hop using the FINAL destination from IP header
        nextHop = call LSRouting.getBestNextHop(modifiedHdr.dest);
        dbg(GENERAL_CHANNEL, "Node %u: Forwarding to dest=%u via nextHop=%u\n", 
            TOS_NODE_ID, modifiedHdr.dest, nextHop);

        if(nextHop == 0){
            dbg(GENERAL_CHANNEL, "Node %u: No route to %u\n", TOS_NODE_ID, modifiedHdr.dest);
            return FAIL;
        }

        // Loop detection
        if(nextHop == originalPkt->src || nextHop == TOS_NODE_ID){
            dbg(GENERAL_CHANNEL, "Node %u: Loop detected\n", TOS_NODE_ID);
            return FAIL;
        }

        // Check payload size
        if(IP_HEADER_LENGTH + len > PACKET_MAX_PAYLOAD_SIZE){
            return FAIL;
        }

        // Serialize the MODIFIED IP header
        memcpy(combinedPayload, (uint8_t*)&modifiedHdr, IP_HEADER_LENGTH);
        
        // Copy the original payload
        if(payload != NULL && len > 0){
            memcpy(combinedPayload + IP_HEADER_LENGTH, payload, len);
        }

        // Create link-layer packet
        makePack(&forwardPack, TOS_NODE_ID, nextHop, MAX_TTL-1, PROTOCOL_IP, originalPkt->seq, combinedPayload, IP_HEADER_LENGTH + len);

        dbg(GENERAL_CHANNEL, "Node %u: Forwarding to nextHop %u\n", TOS_NODE_ID, nextHop);
        call Send.send(forwardPack, nextHop);
        return SUCCESS;
    }

    event message_t* IPReceive.receive(message_t* msg, void* payload, uint8_t len){
        pack* linkPkt;
        uint8_t* dataPayload;
        uint8_t dataLen;
    
        if(len >= sizeof(pack)){
            linkPkt = (pack*)payload;

            if(linkPkt->protocol == PROTOCOL_IP){
                ip_header* receivedHdr = (ip_header*)(linkPkt->payload);
                
                uint16_t ipSrc = receivedHdr->src;
                uint16_t ipDest = receivedHdr->dest;
                uint8_t ipTTL = receivedHdr->TTL;
                uint8_t ipProtocol = receivedHdr->protocol;

                dbg(GENERAL_CHANNEL, "Node %u: Received IP packet src=%u dest=%u TTL=%u\n", 
                    TOS_NODE_ID, ipSrc, ipDest, ipTTL);

                // Drop packets I sent
                if(ipSrc == TOS_NODE_ID){
                    return msg;
                }

                dataPayload = (uint8_t*)(linkPkt->payload + IP_HEADER_LENGTH);
                dataLen = len - (sizeof(pack) - PACKET_MAX_PAYLOAD_SIZE) - IP_HEADER_LENGTH;

                // Check TTL
                if(ipTTL <= 1){
                    return msg;
                }

                // Check if packet is for me
                if(ipDest == TOS_NODE_ID){
                    dbg(GENERAL_CHANNEL, "Node %u: Packet is for me! Protocol=%u\n", TOS_NODE_ID, ipProtocol);
                    if(ipProtocol == PROTOCOL_PING){
                        dbg(GENERAL_CHANNEL, "SUCCESS: Node %u received PING from %u\n", TOS_NODE_ID, ipSrc);
                        signal IPForwarding.receivedPing(ipSrc, dataPayload, dataLen);
                    }
                    return msg;
                }
                else{
                    dbg(GENERAL_CHANNEL, "Node %u: Forwarding packet dest=%u\n", TOS_NODE_ID, ipDest);
                    // Forward the packet using the original header
                    forwardPacket(linkPkt, receivedHdr, dataPayload, dataLen);
                }
            }
        }
        return msg;
    }

    // event void IPForwarding.receivedPing(uint16_t source, uint8_t* payload, uint8_t len) {
    //     // Applications will override this
    // }
}