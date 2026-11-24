#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <pthread.h>
#include <unistd.h>

/* Check the exact glibc LP64 layout, not merely a buffer large enough to work. */
_Static_assert(_Generic((pthread_t)0, unsigned long: 1, default: 0), "pthread_t type");
_Static_assert(sizeof(pthread_t) == 8 && _Alignof(pthread_t) == 8, "pthread_t layout");
_Static_assert(sizeof(pthread_mutex_t) == 40 && _Alignof(pthread_mutex_t) == 8,
               "pthread_mutex_t layout");

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
