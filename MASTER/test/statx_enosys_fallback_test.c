#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <linux/stat.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/sysmacros.h>
#include <sys/types.h>
#include <unistd.h>

#ifndef __NR_statx
int
main(void)
{
    fputs("SKIP: statx syscall number is unavailable on this architecture\n", stderr);
    return 77;
}
#else

static void
statx_from_stat(struct statx *destination, const struct stat *source)
{
    memset(destination, 0, sizeof(*destination));
    destination->stx_mask = STATX_BASIC_STATS;
    destination->stx_blksize = (uint32_t)source->st_blksize;
    destination->stx_nlink = (uint32_t)source->st_nlink;
    destination->stx_uid = (uint32_t)source->st_uid;
    destination->stx_gid = (uint32_t)source->st_gid;
    destination->stx_mode = (uint16_t)source->st_mode;
    destination->stx_atime.tv_sec = source->st_atim.tv_sec;
    destination->stx_atime.tv_nsec = (uint32_t)source->st_atim.tv_nsec;
    destination->stx_mtime.tv_sec = source->st_mtim.tv_sec;
    destination->stx_mtime.tv_nsec = (uint32_t)source->st_mtim.tv_nsec;
    destination->stx_ctime.tv_sec = source->st_ctim.tv_sec;
    destination->stx_ctime.tv_nsec = (uint32_t)source->st_ctim.tv_nsec;
    destination->stx_ino = source->st_ino;
    destination->stx_size = source->st_size;
    destination->stx_blocks = source->st_blocks;
    destination->stx_dev_major = (uint32_t)major(source->st_dev);
    destination->stx_dev_minor = (uint32_t)minor(source->st_dev);
    destination->stx_rdev_major = (uint32_t)major(source->st_rdev);
    destination->stx_rdev_minor = (uint32_t)minor(source->st_rdev);
}

static int
statx_is_unavailable(void)
{
    return errno == ENOSYS || errno == EPERM;
}

static int
statx_path_with_fallback(const char *path, struct statx *destination, unsigned int mask)
{
    int result = (int)syscall(__NR_statx, AT_FDCWD, path, 0, mask, destination);
    if (result == 0 || !statx_is_unavailable()) return result;

    struct stat fallback;
    if (stat(path, &fallback) < 0) return -1;
    statx_from_stat(destination, &fallback);
    return 0;
}

static int
statx_lpath_with_fallback(const char *path, struct statx *destination, unsigned int mask)
{
    int result = (int)syscall(__NR_statx, AT_FDCWD, path, AT_SYMLINK_NOFOLLOW, mask, destination);
    if (result == 0 || !statx_is_unavailable()) return result;

    struct stat fallback;
    if (lstat(path, &fallback) < 0) return -1;
    statx_from_stat(destination, &fallback);
    return 0;
}

static int
statx_fd_with_fallback(int fd, struct statx *destination, unsigned int mask)
{
    int result = (int)syscall(__NR_statx, fd, "", AT_EMPTY_PATH, mask, destination);
    if (result == 0 || !statx_is_unavailable()) return result;

    struct stat fallback;
    if (fstat(fd, &fallback) < 0) return -1;
    statx_from_stat(destination, &fallback);
    return 0;
}

static int
install_statx_filter(int denied_errno)
{
    struct sock_filter instructions[] = {
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, nr)),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_statx, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | (denied_errno & SECCOMP_RET_DATA)),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
    };
    struct sock_fprog program = {
        .len = (unsigned short)(sizeof(instructions) / sizeof(instructions[0])),
        .filter = instructions,
    };
    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) < 0) return -1;
    if (prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &program) < 0) return -1;
    return 0;
}

static int
same_basic_stat(const struct statx *actual, const struct stat *expected)
{
    return (actual->stx_mask & STATX_BASIC_STATS) == STATX_BASIC_STATS &&
        actual->stx_mode == expected->st_mode &&
        actual->stx_nlink == expected->st_nlink &&
        actual->stx_uid == expected->st_uid &&
        actual->stx_gid == expected->st_gid &&
        actual->stx_ino == expected->st_ino &&
        actual->stx_size == (uint64_t)expected->st_size &&
        actual->stx_blocks == (uint64_t)expected->st_blocks &&
        actual->stx_blksize == (uint32_t)expected->st_blksize &&
        actual->stx_dev_major == major(expected->st_dev) &&
        actual->stx_dev_minor == minor(expected->st_dev) &&
        actual->stx_rdev_major == major(expected->st_rdev) &&
        actual->stx_rdev_minor == minor(expected->st_rdev) &&
        actual->stx_atime.tv_sec == expected->st_atim.tv_sec &&
        actual->stx_atime.tv_nsec == expected->st_atim.tv_nsec &&
        actual->stx_mtime.tv_sec == expected->st_mtim.tv_sec &&
        actual->stx_mtime.tv_nsec == expected->st_mtim.tv_nsec &&
        actual->stx_ctime.tv_sec == expected->st_ctim.tv_sec &&
        actual->stx_ctime.tv_nsec == expected->st_ctim.tv_nsec;
}

static int
launch_with_statx_denied(char **command, int denied_errno)
{
    if (install_statx_filter(denied_errno) < 0) {
        if (errno == EPERM || errno == EACCES || errno == ENOSYS) {
            fprintf(stderr, "SKIP: seccomp filter unavailable: %s\\n", strerror(errno));
            return 77;
        }
        perror("install seccomp filter");
        return 1;
    }

    errno = 0;
    if (syscall(__NR_statx, AT_FDCWD, ".", 0, STATX_BASIC_STATS, &(struct statx){0}) != -1 ||
        errno != denied_errno) {
        fprintf(stderr, "FAIL: filter did not deny statx with %s\\n", strerror(denied_errno));
        return 1;
    }

    execv(command[0], command);
    perror("exec Ruby under statx filter");
    return 1;
}

int
main(int argc, char **argv)
{
    if (argc >= 4 && strcmp(argv[1], "--exec") == 0) {
        int denied_errno = strcmp(argv[2], "EPERM") == 0 ? EPERM : ENOSYS;
        return launch_with_statx_denied(&argv[3], denied_errno);
    }

    int denied_errno = argc > 1 && strcmp(argv[1], "EPERM") == 0 ? EPERM : ENOSYS;
    char path[] = "/tmp/statx-fallback-XXXXXX";
    char link_path[sizeof(path) + 8];
    int fd = mkstemp(path);
    if (fd < 0) { perror("mkstemp"); return 1; }
    if (write(fd, "pub4", 4) != 4) { perror("write"); return 1; }
    if (snprintf(link_path, sizeof(link_path), "%s.link", path) < 0) return 1;
    if (symlink(path, link_path) < 0) { perror("symlink"); return 1; }

    struct stat expected_stat, expected_lstat, expected_fstat;
    if (stat(path, &expected_stat) < 0 || lstat(link_path, &expected_lstat) < 0 || fstat(fd, &expected_fstat) < 0) {
        perror("baseline stat"); return 1;
    }
    if (install_statx_filter(denied_errno) < 0) {
        if (errno == EPERM || errno == EACCES || errno == ENOSYS) {
            fprintf(stderr, "SKIP: seccomp filter unavailable: %s\n", strerror(errno));
            return 77;
        }
        perror("install seccomp filter"); return 1;
    }

    struct statx actual;
    memset(&actual, 0, sizeof(actual));
    errno = 0;
    if (syscall(__NR_statx, AT_FDCWD, path, 0, STATX_BASIC_STATS, &actual) != -1 || errno != denied_errno) {
        fprintf(stderr, "FAIL: filter did not deny statx with %s\n", strerror(denied_errno));
        return 1;
    }
    if (statx_path_with_fallback(path, &actual, STATX_BASIC_STATS | STATX_BTIME) < 0 || !same_basic_stat(&actual, &expected_stat)) {
        fprintf(stderr, "FAIL: stat fallback mismatch or error: %s\n", strerror(errno));
        return 1;
    }
    if (actual.stx_mask & STATX_BTIME) {
        fputs("FAIL: stat fallback invented birthtime support\n", stderr);
        return 1;
    }

    memset(&actual, 0, sizeof(actual));
    if (statx_lpath_with_fallback(link_path, &actual, STATX_BASIC_STATS) < 0 ||
        !same_basic_stat(&actual, &expected_lstat) || !S_ISLNK(actual.stx_mode)) {
        fprintf(stderr, "FAIL: lstat fallback mismatch or followed symlink: %s\n", strerror(errno));
        return 1;
    }

    memset(&actual, 0, sizeof(actual));
    if (statx_fd_with_fallback(fd, &actual, STATX_BASIC_STATS) < 0 || !same_basic_stat(&actual, &expected_fstat)) {
        fprintf(stderr, "FAIL: fstat fallback mismatch or error: %s\n", strerror(errno));
        return 1;
    }

    if (statx_path_with_fallback("/definitely-not-a-pub4-file", &actual, STATX_BASIC_STATS) == 0 || errno != ENOENT) {
        fprintf(stderr, "FAIL: fallback did not preserve ENOENT (errno=%d)\n", errno);
        return 1;
    }

    unlink(link_path);
    unlink(path);
    close(fd);
    printf("PASS: stat/lstat/fstat fallback preserved metadata when statx returned %s\n", strerror(denied_errno));
    return 0;
}
#endif
