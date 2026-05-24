/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"

module Node{
   uses interface Boot;

   uses interface SplitControl as AMControl;
   uses interface Receive;

   uses interface SimpleSend as Sender;

   uses interface CommandHandler;
   
   uses interface NeighborDiscovery;
   uses interface Flooding;

   uses interface LSRouting;
   uses interface IPForwarding;

   uses interface Transport;
   uses interface Application;
}

implementation{
   pack sendPackage;
   uint8_t initCount = 0;

   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

   event void Boot.booted(){
      call AMControl.start();
      call IPForwarding.start();

      dbg(GENERAL_CHANNEL, "Booted\n");
   }

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
         
      }else{
         //Retry until successful
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err){}

   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
      dbg(GENERAL_CHANNEL, "Packet Received\n");
      if(len==sizeof(pack)){
         pack* myMsg=(pack*) payload;
         // call Flooding.handleFlood(myMsg->protocol, myMsg->src, myMsg->seq, myMsg->TTL, myMsg->dest, payload);
         dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload);
         return msg;
      }

      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
   }


   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
      // dbg(GENERAL_CHANNEL, "PING EVENT \n");
      call Application.appInject(payload);
   }

   event void CommandHandler.printNeighbors(){
      call NeighborDiscovery.printNeighbors();
   }

   event void CommandHandler.printRouteTable(){
      call LSRouting.printRouteTable();
   }

   event void CommandHandler.printLinkState(){
      // call LSRouting.printLinkState();
   }

   event void CommandHandler.printDistanceVector(){}

   event void CommandHandler.setTestServer(){
      call Application.setTestServer();
   }

   event void CommandHandler.setTestClient(){
      call Application.setTestClient();
   }

   event void CommandHandler.setAppServer(){
      call Application.setAppServer();
   }

   event void CommandHandler.setAppClient(uint16_t port){
      call Application.setAppClient(port);
   }

   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }

   event void NeighborDiscovery.neighborsChanged(){
      // dbg(GENERAL_CHANNEL, "Node %u: Neighbor list changed\n", TOS_NODE_ID);
   }

   event void Flooding.receivedLSA(uint16_t src, uint8_t* lsaData){
      // dbg(GENERAL_CHANNEL, "Node %u: Received LSA from %u\n", TOS_NODE_ID, src);
   }

   event void IPForwarding.packReachedDest(pack* linkPkt, uint8_t len){}

   // event void Transport.connected(socket_t fd){}
}
