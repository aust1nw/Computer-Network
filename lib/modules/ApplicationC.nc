#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendinfo.h"
#include "../../includes/channels.h"

generic configuration ApplicationC(){
    provides interface Application;
}

implementation{
    components new ApplicationP() as App;
    Application = App.Application;

    components new TransportC() as Transport;
    App.Transport -> Transport;

    // components CommandHandlerC;
    // App.CommandHandler -> CommandHandlerC;

    components new TimerMilliC() as Timer1;
    App.Timer1 -> Timer1;
}