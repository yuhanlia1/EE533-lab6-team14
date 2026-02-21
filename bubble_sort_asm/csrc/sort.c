int main(void)
{
    int data[6] = { 5, -1, 2, 4, 10, 8 };
    int n = 6;

    /* bubble sort in main (ascending) */
    int i, j;
    for (i = 0; i < n - 1; i++) {
        for (j = 0; j < n - 1 - i; j++) {
            if (data[j] > data[j + 1]) {
                int t = data[j];
                data[j] = data[j + 1];
                data[j + 1] = t;
            }
        }
    }

    return 0;
}
