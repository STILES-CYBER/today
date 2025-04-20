#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    // Check if the correct number of arguments is provided
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <file> <text>\n", argv[0]);
        return 1;
    }

    const char *filename = argv[1];
    const char *text = argv[2];

    // Open the file for writing
    FILE *file = fopen(filename, "w");
    if (!file) {
        perror("Error opening file");
        return 1;
    }

    // Write the string to the file
    if (fprintf(file, "%s\n", text) < 0) {
        perror("Error writing to file");
        fclose(file);
        return 1;
    }

    // Close the file
    fclose(file);

    return 0;
}
