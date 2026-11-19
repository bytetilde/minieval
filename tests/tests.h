#pragma once
#include <stdio.h>  // IWYU pragma: keep
#include <stdlib.h> // IWYU pragma: keep

#define TESTS_MAX 4096
#define TESTS_TIMEOUT 5

#define TEST_CONCAT_(a, b) a##b
#define TEST_CONCAT(a, b) TEST_CONCAT_(a, b)
#define TEST_INNER(name, tag, id)                                                                  \
  static const char* TEST_CONCAT(test_fn_, id)(void);                                              \
  __attribute__((constructor)) static void TEST_CONCAT(test_reg_, id)(void) {                      \
    if(ntests >= TESTS_MAX) {                                                                      \
      fprintf(stderr, "too many tests (max %d)\n", TESTS_MAX);                                     \
      abort();                                                                                     \
    }                                                                                              \
    tests[ntests++] = (me_test_t){name, tag, TEST_CONCAT(test_fn_, id)};                           \
  }                                                                                                \
  static const char* TEST_CONCAT(test_fn_, id)(void)
#define TEST(name, tag) TEST_INNER(name, tag, __COUNTER__)

#define TEST_ASSERT(cond, message)                                                                 \
  do {                                                                                             \
    if(!(cond)) return (message);                                                                  \
  } while(0)
#define TEST_ASSERTF(cond, fmt, ...)                                                               \
  do {                                                                                             \
    static char TEST_CONCAT(testmsg, __LINE__)[512];                                               \
    if(!(cond)) {                                                                                  \
      snprintf(TEST_CONCAT(testmsg, __LINE__), sizeof(TEST_CONCAT(testmsg, __LINE__)),             \
               fmt, ##__VA_ARGS__);                                                                \
      return TEST_CONCAT(testmsg, __LINE__);                                                       \
    }                                                                                              \
  } while(0)
#define TEST_CHECK(message)                                                                        \
  do {                                                                                             \
    const char* const testcheck = (message);                                                       \
    if(testcheck) return testcheck;                                                                \
  } while(0)
#define TEST_SUCCESS() return NULL

typedef struct me_test_t {
  const char* name;
  const char* tag;
  const char* (*fn)(void);
} me_test_t;

extern me_test_t tests[TESTS_MAX];
extern int ntests;
