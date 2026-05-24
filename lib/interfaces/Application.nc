interface Application{
    command void setTestServer();
    command void setTestClient();
    command void setAppServer();
    command void setAppClient(uint16_t port);
    command void appInject(uint8_t* line);
}