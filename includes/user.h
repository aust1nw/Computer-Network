#ifndef USER_H
#define USER_H

#define CHAT_MAX_NAME 16

typedef struct{
    bool used;
    char name[CHAT_MAX_NAME+1];
} user_t;

#endif // USER_H