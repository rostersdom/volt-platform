#define _GNU_SOURCE
#include <dlfcn.h>
#include <pthread.h>
#include <sched.h>
#include <stdatomic.h>
#include <unistd.h>

static atomic_int entered;

/* Publish while still holding the channel mutex; close/drop cannot acquire it
 * until the real condition wait has atomically registered and released it. */
int pthread_cond_wait(pthread_cond_t *condition, pthread_mutex_t *mutex) {
    typedef int (*Wait)(pthread_cond_t *, pthread_mutex_t *);
    Wait wait = (Wait)dlsym(RTLD_NEXT, "pthread_cond_wait");
    if (!wait) _exit(70);
    atomic_store(&entered, 1);
    return wait(condition, mutex);
}

void volt_channel_wait_probe(void) {
    while (!atomic_load(&entered)) sched_yield();
}

void volt_channel_wait_reset(void) {
    atomic_store(&entered, 0);
}
