#include <stdlib.h>
#include <stdbool.h>
#include <stdarg.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <sys/wait.h>

// Implementation of do_system
bool do_system(const char *cmd) {
    if (cmd == NULL) {
        return false; // Invalid command
    }

    int ret = system(cmd);
    return (ret == 0); // Return true if system() succeeded
}
// Implementation of do_exec
bool do_exec(int count, ...) {
    va_list args;
    va_start(args, count);
    
    char *command[count + 1];
    for (int i = 0; i < count; i++) {
        command[i] = va_arg(args, char *);
    }
    command[count] = NULL; // Null-terminate the array

    pid_t pid = fork();
    if (pid == -1) {
        va_end(args);
        return false; // Fork failed
    }

    if (pid == 0) {
        // Child process
        execv(command[0], command);
        _exit(EXIT_FAILURE); // If execv fails
    }

    // Parent process
    int status;
    pid_t wait_ret = waitpid(pid, &status, 0);
    va_end(args);

    if (wait_ret == -1 || !WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        return false; // Error in waitpid or command execution
    }

    return true; // Success
}
// Implementation of do_exec_redirect
bool do_exec_redirect(const char *outputfile, int count, ...) {
    va_list args;
    va_start(args, count);

    char *command[count + 1];
    for (int i = 0; i < count; i++) {
        command[i] = va_arg(args, char *);
    }
    command[count] = NULL; // Null-terminate the array

    pid_t pid = fork();
    if (pid == -1) {
        va_end(args);
        return false; // Fork failed
    }

    if (pid == 0) {
        // Child process
        int fd = open(outputfile, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd == -1) {
            _exit(EXIT_FAILURE); // File open failed
        }

        dup2(fd, STDOUT_FILENO); // Redirect stdout to the file
        close(fd);

        execv(command[0], command);
        _exit(EXIT_FAILURE); // If execv fails
    }

    // Parent process
    int status;
    pid_t wait_ret = waitpid(pid, &status, 0);
    va_end(args);

    if (wait_ret == -1 || !WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        return false; // Error in waitpid or command execution
    }

    return true; // Success
}
