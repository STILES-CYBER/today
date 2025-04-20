#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc < 3) {
        fprintf(stderr, "Usage: %s <file> <text>\n", argv[0]);
        return 1;
    }

    const char *filename = argv[1];
    const char *text = argv[2];

    FILE *file = fopen(filename, "w");
    if (!file) {
        perror("Error opening file");
        return 1;
    }

    fprintf(file, "%s\n", text);
    fclose(file);

    return 0;
}
