// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#include "platform/globals.h"  // NOLINT
#if defined(TARGET_OS_MACOS)

#include "vm/os_thread.h"

#include <sys/errno.h>  // NOLINT
#include <sys/types.h>  // NOLINT
#include <sys/sysctl.h>  // NOLINT
#include <mach/mach_init.h>  // NOLINT
#include <mach/mach_host.h>  // NOLINT
#include <mach/mach_port.h>  // NOLINT
#include <mach/mach_traps.h>  // NOLINT
#include <mach/task_info.h>  // NOLINT
#include <mach/thread_info.h>  // NOLINT
#include <mach/thread_act.h>  // NOLINT

#include "platform/assert.h"

namespace dart {

#define VALIDATE_PTHREAD_RESULT(result)         \
  if (result != 0) { \
    const int kBufferSize = 1024; \
    char error_message[kBufferSize]; \
    strerror_r(result, error_message, kBufferSize); \
    FATAL2("pthread error: %d (%s)", result, error_message); \
  }


#if defined(DEBUG)
#define ASSERT_PTHREAD_SUCCESS(result) VALIDATE_PTHREAD_RESULT(result)
#else
// NOTE: This (currently) expands to a no-op.
#define ASSERT_PTHREAD_SUCCESS(result) ASSERT(result == 0)
#endif


#ifdef DEBUG
#define RETURN_ON_PTHREAD_FAILURE(result) \
  if (result != 0) { \
    const int kBufferSize = 1024; \
    char error_message[kBufferSize]; \
    strerror_r(result, error_message, kBufferSize); \
    fprintf(stderr, "%s:%d: pthread error: %d (%s)\n", \
            __FILE__, __LINE__, result, error_message); \
    return result; \
  }
#else
#define RETURN_ON_PTHREAD_FAILURE(result) \
  if (result != 0) return result;
#endif


class ThreadStartData {
 public:
  ThreadStartData(OSThread::ThreadStartFunction function,
                  uword parameter)
      : function_(function), parameter_(parameter) {}

  OSThread::ThreadStartFunction function() const { return function_; }
  uword parameter() const { return parameter_; }

 private:
  OSThread::ThreadStartFunction function_;
  uword parameter_;

  DISALLOW_COPY_AND_ASSIGN(ThreadStartData);
};


// Dispatch to the thread start function provided by the caller. This trampoline
// is used to ensure that the thread is properly destroyed if the thread just
// exits.
static void* ThreadStart(void* data_ptr) {
  ThreadStartData* data = reinterpret_cast<ThreadStartData*>(data_ptr);

  OSThread::ThreadStartFunction function = data->function();
  uword parameter = data->parameter();
  delete data;

  // Call the supplied thread start function handing it its parameters.
  function(parameter);

  return NULL;
}


int OSThread::Start(ThreadStartFunction function, uword parameter) {
  pthread_attr_t attr;
  int result = pthread_attr_init(&attr);
  RETURN_ON_PTHREAD_FAILURE(result);

  result = pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
  RETURN_ON_PTHREAD_FAILURE(result);

  result = pthread_attr_setstacksize(&attr, OSThread::GetMaxStackSize());
  RETURN_ON_PTHREAD_FAILURE(result);

  ThreadStartData* data = new ThreadStartData(function, parameter);

  pthread_t tid;
  result = pthread_create(&tid, &attr, ThreadStart, data);
  RETURN_ON_PTHREAD_FAILURE(result);

  result = pthread_attr_destroy(&attr);
  RETURN_ON_PTHREAD_FAILURE(result);

  return 0;
}


ThreadLocalKey OSThread::kUnsetThreadLocalKey =
    static_cast<pthread_key_t>(-1);
ThreadId OSThread::kInvalidThreadId = reinterpret_cast<ThreadId>(NULL);

ThreadLocalKey OSThread::CreateThreadLocal(ThreadDestructor destructor) {
  pthread_key_t key = kUnsetThreadLocalKey;
  int result = pthread_key_create(&key, destructor);
  VALIDATE_PTHREAD_RESULT(result);
  ASSERT(key != kUnsetThreadLocalKey);
  return key;
}


void OSThread::DeleteThreadLocal(ThreadLocalKey key) {
  ASSERT(key != kUnsetThreadLocalKey);
  int result = pthread_key_delete(key);
  VALIDATE_PTHREAD_RESULT(result);
}


void OSThread::SetThreadLocal(ThreadLocalKey key, uword value) {
  ASSERT(key != kUnsetThreadLocalKey);
  int result = pthread_setspecific(key, reinterpret_cast<void*>(value));
  VALIDATE_PTHREAD_RESULT(result);
}


intptr_t OSThread::GetMaxStackSize() {
  const int kStackSize = (128 * kWordSize * KB);
  return kStackSize;
}


ThreadId OSThread::GetCurrentThreadId() {
  return pthread_self();
}


bool OSThread::Join(ThreadId id) {
  return false;
}


intptr_t OSThread::ThreadIdToIntPtr(ThreadId id) {
  ASSERT(sizeof(id) == sizeof(intptr_t));
  return reinterpret_cast<intptr_t>(id);
}


bool OSThread::Compare(ThreadId a, ThreadId b) {
  return pthread_equal(a, b) != 0;
}


void OSThread::GetThreadCpuUsage(ThreadId thread_id, int64_t* cpu_usage) {
  ASSERT(thread_id == GetCurrentThreadId());
  ASSERT(cpu_usage != NULL);
  // TODO(johnmccutchan): Enable this after fixing issue with macos directory
  // watcher.
  const bool get_cpu_usage = false;
  if (get_cpu_usage) {
    mach_msg_type_number_t count = THREAD_BASIC_INFO_COUNT;
    thread_basic_info_data_t info_data;
    thread_basic_info_t info = &info_data;
    mach_port_t thread_port = mach_thread_self();
    kern_return_t r = thread_info(thread_port, THREAD_BASIC_INFO,
                                  (thread_info_t)info, &count);
    mach_port_deallocate(mach_task_self(), thread_port);
    if (r == KERN_SUCCESS) {
      *cpu_usage = (info->user_time.seconds * kMicrosecondsPerSecond) +
                   info->user_time.microseconds;
      return;
    }
  }
  *cpu_usage = 0;
}


Mutex::Mutex() {
  pthread_mutexattr_t attr;
  int result = pthread_mutexattr_init(&attr);
  VALIDATE_PTHREAD_RESULT(result);

#if defined(DEBUG)
  result = pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_ERRORCHECK);
  VALIDATE_PTHREAD_RESULT(result);
#endif  // defined(DEBUG)

  result = pthread_mutex_init(data_.mutex(), &attr);
  // Verify that creating a pthread_mutex succeeded.
  VALIDATE_PTHREAD_RESULT(result);

  result = pthread_mutexattr_destroy(&attr);
  VALIDATE_PTHREAD_RESULT(result);

  // When running with assertions enabled we do track the owner.
#if defined(DEBUG)
  owner_ = OSThread::kInvalidThreadId;
#endif  // defined(DEBUG)
}


Mutex::~Mutex() {
  int result = pthread_mutex_destroy(data_.mutex());
  // Verify that the pthread_mutex was destroyed.
  VALIDATE_PTHREAD_RESULT(result);

  // When running with assertions enabled we do track the owner.
#if defined(DEBUG)
  ASSERT(owner_ == OSThread::kInvalidThreadId);
#endif  // defined(DEBUG)
}


void Mutex::Lock() {
  int result = pthread_mutex_lock(data_.mutex());
  // Specifically check for dead lock to help debugging.
  ASSERT(result != EDEADLK);
  ASSERT_PTHREAD_SUCCESS(result);  // Verify no other errors.
  // When running with assertions enabled we do track the owner.
#if defined(DEBUG)
  owner_ = OSThread::GetCurrentThreadId();
#endif  // defined(DEBUG)
}


bool Mutex::TryLock() {
  int result = pthread_mutex_trylock(data_.mutex());
  // Return false if the lock is busy and locking failed.
  if ((result == EBUSY) || (result == EDEADLK)) {
    return false;
  }
  ASSERT_PTHREAD_SUCCESS(result);  // Verify no other errors.
  // When running with assertions enabled we do track the owner.
#if defined(DEBUG)
  owner_ = OSThread::GetCurrentThreadId();
#endif  // defined(DEBUG)
  return true;
}


void Mutex::Unlock() {
  // When running with assertions enabled we do track the owner.
#if defined(DEBUG)
  ASSERT(IsOwnedByCurrentThread());
  owner_ = OSThread::kInvalidThreadId;
#endif  // defined(DEBUG)
  int result = pthread_mutex_unlock(data_.mutex());
  // Specifically check for wrong thread unlocking to aid debugging.
  ASSERT(result != EPERM);
  ASSERT_PTHREAD_SUCCESS(result);  // Verify no other errors.
}


Monitor::Monitor() {
  pthread_mutexattr_t attr;
  int result = pthread_mutexattr_init(&attr);
  VALIDATE_PTHREAD_RESULT(result);

#if defined(DEBUG)
  result = pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_ERRORCHECK);
  VALIDATE_PTHREAD_RESULT(result);
#endif  // defined(DEBUG)

  result = pthread_mutex_init(data_.mutex(), &attr);
  VALIDATE_PTHREAD_RESULT(result);

  result = pthread_mutexattr_destroy(&attr);
  VALIDATE_PTHREAD_RESULT(result);

  result = pthread_cond_init(data_.cond(), NULL);
  VALIDATE_PTHREAD_RESULT(result);
}


Monitor::~Monitor() {
  int result = pthread_mutex_destroy(data_.mutex());
  VALIDATE_PTHREAD_RESULT(result);

  result = pthread_cond_destroy(data_.cond());
  VALIDATE_PTHREAD_RESULT(result);
}


void Monitor::Enter() {
  int result = pthread_mutex_lock(data_.mutex());
  VALIDATE_PTHREAD_RESULT(result);
  // TODO(iposva): Do we need to track lock owners?
}


void Monitor::Exit() {
  // TODO(iposva): Do we need to track lock owners?
  int result = pthread_mutex_unlock(data_.mutex());
  VALIDATE_PTHREAD_RESULT(result);
}


Monitor::WaitResult Monitor::Wait(int64_t millis) {
  return WaitMicros(millis * kMicrosecondsPerMillisecond);
}


Monitor::WaitResult Monitor::WaitMicros(int64_t micros) {
  // TODO(iposva): Do we need to track lock owners?
  Monitor::WaitResult retval = kNotified;
  if (micros == kNoTimeout) {
    // Wait forever.
    int result = pthread_cond_wait(data_.cond(), data_.mutex());
    VALIDATE_PTHREAD_RESULT(result);
  } else {
    struct timespec ts;
    int64_t secs = micros / kMicrosecondsPerSecond;
    if (secs > kMaxInt32) {
      // Avoid truncation of overly large timeout values.
      secs = kMaxInt32;
    }
    int64_t nanos =
        (micros - (secs * kMicrosecondsPerSecond)) * kNanosecondsPerMicrosecond;
    ts.tv_sec = static_cast<int32_t>(secs);
    ts.tv_nsec = static_cast<long>(nanos);  // NOLINT (long used in timespec).
    int result = pthread_cond_timedwait_relative_np(data_.cond(),
                                                    data_.mutex(),
                                                    &ts);
    ASSERT((result == 0) || (result == ETIMEDOUT));
    if (result == ETIMEDOUT) {
      retval = kTimedOut;
    }
  }
  return retval;
}


void Monitor::Notify() {
  // TODO(iposva): Do we need to track lock owners?
  int result = pthread_cond_signal(data_.cond());
  VALIDATE_PTHREAD_RESULT(result);
}


void Monitor::NotifyAll() {
  // TODO(iposva): Do we need to track lock owners?
  int result = pthread_cond_broadcast(data_.cond());
  VALIDATE_PTHREAD_RESULT(result);
}

}  // namespace dart

#endif  // defined(TARGET_OS_MACOS)
