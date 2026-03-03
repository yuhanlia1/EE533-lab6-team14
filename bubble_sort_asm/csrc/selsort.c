int main(void)
{
    int data[6] = { 5, -1, 2, 4, 10, 8 };
    int n = 6;

    /* selection sort in main (ascending) */
    int i, j;
    for (i = 0; i < n - 1; i++) {
        int min_idx = i;                 // 假设当前位置 i 是最小值下标
        for (j = i + 1; j < n; j++) {    // 在 [i+1, n-1] 里找更小的
            if (data[j] < data[min_idx]) {
                min_idx = j;
            }
        }
        if (min_idx != i) {              // 把最小值换到位置 i
            int t = data[i];
            data[i] = data[min_idx];
            data[min_idx] = t;
        }
    }

    return 0;
}
