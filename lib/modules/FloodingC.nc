// #include <Timer.h>
// #include "../../includes/channel.h"

// generic configuration FloodingC(){
//     provides interface Flooding:

// }
// implementation{
//     components new FloodingP();

//     Flooding = FloodingP.Flooding;

//     components new AMReceiverC(AM_PACK) as PingReceive;
//     components ActiveMessageC;

//     FloodingP.Receive -> PingReceive;
//     FloodingP.AMControl -> ActiveMessageC;

//     components new TimerMilliC() as Timer1;
//     components RandomC as Random;
    
//     FloodingP.Timer1 -> Timer1;
//     FloodingP.Random -> Random;
// }
