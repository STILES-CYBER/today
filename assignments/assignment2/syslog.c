#include <stdio.h>
#include <stdlib.h>
#include <syslog.h>
#include <string.h>

int main(int argc, char *argv[]) {
    // Check for correct number of arguments
    if (argc != 3) {
        printf("Usage: %s <string> <file>\n", argv[0]);
        syslog(LOG_ERR, "Error: Incorrect number of arguments");
        exit(EXIT_FAILURE);
    }

    const char *string = argv[1];
    const char *file = argv[2];

    // Initialize syslog
    openlog("writer_utility", LOG_PID | LOG_CONS, LOG_USER);

    // Open the file for writing
    FILE *fp = fopen(file, "w");
    if (fp == NULL) {
        syslog(LOG_ERR, "Error: Unable to open file %s", file);
        perror("fopen");
        closelog();
        exit(EXIT_FAILURE);
    }

    // Write the string to the file
    if (fprintf(fp, "%s", string) < 0) {
        syslog(LOG_ERR, "Error: Failed to write to file %s", file);
        perror("fprintf");
        fclose(fp);
        closelog();
        exit(EXIT_FAILURE);
    }

    // Log successful write
    syslog(LOG_DEBUG, "Writing %s to %s", string, file);

    // Clean up
    fclose(fp);
    closelog();

    return 0;
}
