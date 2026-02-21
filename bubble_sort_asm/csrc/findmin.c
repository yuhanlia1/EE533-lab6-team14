int main(){
    int a[]={5,2,9,1,3};
    int n=5,t;
    for(int i=0;i<n-1;i++){
        int min=i;
        for(int j=i+1;j<n;j++)
            if(a[j]<a[min]) min=j;
        t=a[i]; a[i]=a[min]; a[min]=t;
    }
    return 0;
}
