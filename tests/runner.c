#include "tests.h"
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

me_test_t tests[TESTS_MAX];
int ntests = 0;

static bool log_pass(int i, me_test_t test) {
  printf("[%04d/%04d] PASS: %s (%s)\n", i + 1, ntests, test.name, test.tag);
  fflush(stdout);
  return true;
}
static bool log_fail(int i, me_test_t test, const char* message) {
  printf("[%04d/%04d] FAIL: %s (%s): %s\n", i + 1, ntests, test.name, test.tag, message);
  fflush(stdout);
  return false;
}

static bool run_test(int i, me_test_t test, bool verbose) {
  fflush(stdout);
  const pid_t pid = fork();
  if(pid == -1) return log_fail(i, test, "fork failed");
  if(pid == 0) {
    alarm(TESTS_TIMEOUT);
    const char* const message = test.fn();
    if(message) {
      log_fail(i, test, message);
      _exit(1);
    }
    if(verbose) log_pass(i, test);
    _exit(0);
  }
  int status;
  if(waitpid(pid, &status, 0) == -1) return log_fail(i, test, "waitpid failed");
  if(WIFEXITED(status)) return WEXITSTATUS(status) == 0;
  if(!WIFSIGNALED(status)) return log_fail(i, test, "unexpected wait status");
  const int sig = WTERMSIG(status);
  if(sig == SIGALRM) return log_fail(i, test, "timed out");
  if(sig == SIGSEGV) return log_fail(i, test, "segmentation fault");
  if(sig == SIGABRT) return log_fail(i, test, "aborted");
  char buf[64];
  snprintf(buf, sizeof(buf), "killed by signal %d", sig);
  return log_fail(i, test, buf);
}

static bool tag_matches(const char* tag, const char* filter, size_t filterlen) {
  if(strncmp(tag, filter, filterlen) != 0) return false;
  return !tag[filterlen] || tag[filterlen] == '/' || filter[filterlen - 1] == '/';
}

int main(int argc, char** argv) {
  const char* const filter = argc > 1 && argv[1][0] ? argv[1] : NULL;
  const size_t filterlen = filter ? strlen(filter) : 0;
  int passed = 0, total = 0;
  for(int i = 0; i < ntests; ++i) {
    if(filter && !tag_matches(tests[i].tag, filter, filterlen)) continue;
    if(run_test(i, tests[i], filter != NULL)) ++passed;
    ++total;
  }
  if(total) printf("%d/%d passed (%.2f%%)\n", passed, total, (double)passed / total * 100);
  else printf("no tests\n");
  return passed != total;
}
