#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <pthread.h>
#include <stddef.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

/* Check the exact glibc LP64 layout, not merely a buffer large enough to work. */
_Static_assert(_Generic((pthread_t)0, unsigned long: 1, default: 0), "pthread_t type");
_Static_assert(sizeof(pthread_t) == 8 && _Alignof(pthread_t) == 8, "pthread_t layout");
_Static_assert(sizeof(pthread_mutex_t) == 40 && _Alignof(pthread_mutex_t) == 8,
               "pthread_mutex_t layout");
_Static_assert(sizeof(pthread_cond_t) == 48 && _Alignof(pthread_cond_t) == 8,
               "pthread_cond_t layout");
_Static_assert(sizeof(struct timespec) == 16 && _Alignof(struct timespec) == 8 &&
               offsetof(struct timespec, tv_sec) == 0 && offsetof(struct timespec, tv_nsec) == 8,
               "timespec layout");
_Static_assert(sizeof(clockid_t) == 4 && CLOCK_MONOTONIC == 1, "CLOCK_MONOTONIC ABI");
_Static_assert(EAGAIN == 11 && EBUSY == 16 && EINVAL == 22 && EDEADLK == 35 && ETIMEDOUT == 110,
               "pthread error numbers");

/* Only the single owner makes these calls. Fail the first call to each, then
 * forward to glibc so the retry still exercises real resource reclamation. */
int pthread_create(pthread_t *out, const pthread_attr_t *attr,
                   void *(*entry)(void *), void *data) {
    static int calls;
    if (++calls == 1) {
        *out = 1;  /* A failed create makes the pthread output unspecified. */
        return EAGAIN;
    }
    if (calls != 2) _exit(62);
    typedef int (*Create)(pthread_t *, const pthread_attr_t *, void *(*)(void *), void *);
    Create create = (Create)dlsym(RTLD_NEXT, "pthread_create");
    if (!create) _exit(60);
    return create(out, attr, entry, data);
}

int pthread_join(pthread_t id, void **out) {
    static int calls;
    if (++calls == 1) return EDEADLK;
    if (calls != 2) _exit(63);  /* Reject a second real join, even if libc would return EINVAL. */
    typedef int (*Join)(pthread_t, void **);
    Join join = (Join)dlsym(RTLD_NEXT, "pthread_join");
    if (!join) _exit(61);
    return join(id, out);
}

/* Fail the first init/destroy, then delegate. A failed init may leave dirty
 * storage, but a failed destroy must leave the live object usable for retry. */
int pthread_mutex_init(pthread_mutex_t *mutex, const pthread_mutexattr_t *attr) {
    static int calls;
    if (++calls == 1) {
        memset(mutex, 0xa5, sizeof(*mutex));
        return EAGAIN;
    }
    if (calls != 2) _exit(64);
    typedef int (*Init)(pthread_mutex_t *, const pthread_mutexattr_t *);
    Init init = (Init)dlsym(RTLD_NEXT, "pthread_mutex_init");
    if (!init) _exit(65);
    return init(mutex, attr);
}

int pthread_mutex_destroy(pthread_mutex_t *mutex) {
    static int calls;
    if (++calls == 1) return EBUSY;
    if (calls != 2) _exit(66);
    typedef int (*Destroy)(pthread_mutex_t *);
    Destroy destroy = (Destroy)dlsym(RTLD_NEXT, "pthread_mutex_destroy");
    if (!destroy) _exit(67);
    return destroy(mutex);
}

int pthread_cond_init(pthread_cond_t *condition, const pthread_condattr_t *attr) {
    static int calls;
    if (++calls == 1) {
        memset(condition, 0xa5, sizeof(*condition));
        return EAGAIN;
    }
    if (calls != 2) _exit(68);
    typedef int (*Init)(pthread_cond_t *, const pthread_condattr_t *);
    Init init = (Init)dlsym(RTLD_NEXT, "pthread_cond_init");
    if (!init) _exit(69);
    return init(condition, attr);
}

int pthread_cond_destroy(pthread_cond_t *condition) {
    static int calls;
    if (++calls == 1) return EBUSY;
    if (calls != 2) _exit(70);
    typedef int (*Destroy)(pthread_cond_t *);
    Destroy destroy = (Destroy)dlsym(RTLD_NEXT, "pthread_cond_destroy");
    if (!destroy) _exit(71);
    return destroy(condition);
}
