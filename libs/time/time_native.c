#include <time.h>
#include <sys/time.h>

long long time_now_millis(void) {
  struct timespec ts;
  if (clock_gettime(CLOCK_REALTIME, &ts) == 0) {
    return (long long) ts.tv_sec * 1000LL + ts.tv_nsec / 1000000LL;
  }
  return (long long) time(NULL) * 1000LL;
}
