
#define ANN_HEADER
#include "net_2_32_32_5_double.c"
#include "data_set.hpp"
#include <math.h>
#include <signal.h>

using namespace std;

typedef double ValueType;

template<typename T>
bool compute_err(
    DataSet<T>& data, 
    T* mem,
    T *(*fw)(T *in, T *mem),
    T& sse,
    T& max)
{
    int i, j;
    T sum = 0, v;
    max = 0;
    
    T *computed_dn, *expected_dn;
    computed_dn = new T[data.nOuts()];
    expected_dn = new T[data.nOuts()];
    
    for (i=0; i<data.numSamples(); i++) {
        T *s = data.getSample(i);
        
        T *computed = fw(data.getIns(s), mem);
        T *expected = data.getOuts(s);
        data.denormalizeOuts(computed, computed_dn);
        data.denormalizeOuts(expected, expected_dn);
        
        for (j=0; j<data.nOuts(); j++) {
            if (!isfinite(computed[j])) return false;            
            v = computed_dn[j] - expected_dn[j];
            v = fabs(v);
//            if (v > 10) printf("Wanted %f, got %f\n", expected_dn[j], computed_dn[j]);
            if (v > max) max = v;
            sum += v*v;
        }
    }
    sum /= (data.numSamples() * data.nOuts());
    sse = sqrt(sum);
    
    delete [] computed_dn;
    delete [] expected_dn;
    
    return true;
}

template<typename T>
void training_epoch(
    DataSet<T>& data,
    T* mem,
    T *(*fw)(T *in, T *mem),
    void (*bk)(T *des, T *mem, T lr),
    T lr)
{
    int i;
    for (i=0; i<data.numSamples(); i++) {
        T *s = data.getSample(i);
        T *o = fw(data.getIns(s), mem);
        // printf("s%d ", i);
        // for (int j=0; j<data.nOuts(); j++) {
        //     printf("%g ", o[j]);
        // }
        // printf("\n");
        bk(data.getOuts(s), mem, lr);
    }
}

template<typename T>
T find_learning_rate(T old_lr, DataSet<T>& data, 
    T* mem,
    T *(*fw)(T *in, T *mem),
    void (*bk)(T *des, T *mem, T lr),
    long memsize)
{
    T *backup = (T*)malloc(memsize);
    bool up = false, did_up = false, did_down = false;
    T last_sse, sse, max, last_max;
    T r_down = 0.99;
    T r_up = 1.0 / r_down;
    bool good;
    
    compute_err(data, mem, fw, last_sse, last_max);

    int i = 0;
    while ((!did_up || !did_down) && i<10) {
        memcpy(backup, mem, memsize);
        sse = 1000000;
        max = 1000000;
        for (int j=0; j<10; j++) {
            training_epoch(data, mem, fw, bk, old_lr * 2.0f);
            double ssei, maxi;
            good = compute_err(data, mem, fw, ssei, maxi);
            //sse += ssei;
            //max += maxi;
            //if (ssei < sse) sse = ssei;
            //if (maxi < max) max = maxi;
            sse = ssei;
            max = maxi;
        }
        //sse /= 2;
        //max /= 2;
        memcpy(mem, backup, memsize);
        
        if (sse > last_sse && max > last_max) good = false;
        if (!isfinite(sse) || !isfinite(max) || fabs(sse) > 1000000000.0 || fabs(max) > 1000000000.0) {
            good = false;
            i = 0;
        }
        
        if (good) {
            old_lr *= r_up;
            did_up = true;
        } else {
            old_lr *= r_down;
            did_down = true;
        }        
        
        i++;
        //cout << old_lr << " " << last_sse << " " << sse << endl;
    }
    
    free(backup);
    return old_lr;
}


int global_quit = 0;
static void catch_sigint(int signo) {
    global_quit = 1;
}

int main()
{
    
    //asm("fnclex");
    //asm("fldcw _fpflags");
    
    DataSet<ValueType> data(2, 5);
    data.loadFile("iioxxxxxoxxxxxoxxxxxoxxxxxoxxxxx", "sampleOut3.csv");
    data.randomOrder();
    //data.dump();
    data.normalize();
    //data.dump();
    
    ValueType *mem = allocate_2_32_32_5l();
    randomize_2_32_32_5l(mem);
    
    ValueType lr = 0.10;
    ValueType sse, max;
    ValueType best_sse = 1000000, best_max = 1000000;
    
    signal(SIGINT, catch_sigint);
    
    compute_err(data, mem, forward_2_32_32_5l, sse, max);
    cout << lr << " " << sse << " " << max << endl;
    for (int i=0; i<1000000 && !global_quit; i++) {
        lr = find_learning_rate(lr, data, mem, forward_2_32_32_5l, backward_2_32_32_5l, MEM_SIZE_2_32_32_5l);    
        for (int j=0; j<1000; j++) {
            //printf("%d    \r", j);
            //fflush(stdout);
            training_epoch(data, mem, forward_2_32_32_5l, backward_2_32_32_5l, lr);
        }
        compute_err(data, mem, forward_2_32_32_5l, sse, max);
        cout << lr << " " << sse << " " << max << endl;
        
        if (sse < best_sse || max < best_max) {
            best_sse = sse;
            best_max = max;
            
            FILE *out = fopen("weights-2l.net", "wb");
            fwrite(mem, 1, MEM_SIZE_2_32_32_5l, out);
            fclose(out);
        }
    }
}
