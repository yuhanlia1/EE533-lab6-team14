int main(){
    int a=1,b=1,c;
    for(int i=3;i<=20;i++){
        c=a+b;
        a=b;
        b=c;
    }
    return 0;
}
