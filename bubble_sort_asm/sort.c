void bubble_sort(int *a, int n)
{
    int i, j;
    for (i = 0; i < n - 1; i++) {
        for (j = 0; j < n - 1 - i; j++) {
            if (a[j] > a[j + 1]) {
                int t = a[j];
                a[j] = a[j + 1];
                a[j + 1] = t;
            }
        }
    }
}

int main(void)
{
    int data[6] = { 5, 1, 2, 4, 8, 10 };
    
    bubble_sort(data, 6);

    return 0;
}

