generic configuration TransportC(){
  provides interface Transport;
}

implementation {
    components new TransportP();
    Transport = TransportP.Transport;
  
    components ActiveMessageC;
    TransportP.Packet -> ActiveMessageC;

    components new SimpleSendC(AM_PACK) as Send;
    TransportP.Send -> Send;

    components new TimerMilliC() as TCPTimer;
    TransportP.TCPTimer -> TCPTimer;
    
    components RandomC as Random;
    TransportP.Random -> Random;

    components new IPForwardingC() as IPForwarding;
    TransportP.IPForwarding -> IPForwarding;
}