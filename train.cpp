
#define ANN_HEADER
#include "annt.c"
#include "data_set.hpp"
#include <math.h>
#include <signal.h>

using namespace std;

typedef float ValueType;

double min_exp, max_exp, min_com, max_com, avg_com, avg_exp;

template<typename T>
bool compute_err(
    DataSet<T>& data, 
    T* mem,
    T *(*fw)(T *in, T *mem),
    T& sse,
    T& max,
    T& cerr)
{
    int i, j;
    T sum = 0, v;
    max = 0;
    cerr = 0;

    min_exp = 1000;
    max_exp = -1000;
    min_com = 1000;
    max_com = -1000;
    avg_com = 0;
    avg_exp = 0;
    
    T *computed_dn, *expected_dn;
    //computed_dn = new T[data.nOuts()];
    //expected_dn = new T[data.nOuts()];
    
    for (i=0; i<data.numSamples(); i++) {
        T *s = data.getSample(i);
        
        T *computed = fw(data.getIns(s), mem);
        T *expected = data.getOuts(s);
        //data.denormalizeOuts(computed, computed_dn);
        //data.denormalizeOuts(expected, expected_dn);
        computed_dn = computed;
        expected_dn = expected;

        if (expected[0] < min_exp) min_exp = expected[0];
        if (expected[0] > max_exp) max_exp = expected[0];
        if (computed[0] < min_com) min_com = computed[0];
        if (computed[0] > max_com) max_com = computed[0];
        avg_com += computed[0];
        avg_exp += expected[0];
        if (computed[0] > 0 && expected[0] < 0) {
            cerr++;
        } else if (computed[0] < 0 && expected[0] > 0) {
            cerr++;
        }
        
        for (j=0; j<data.nOuts(); j++) {
            if (!isfinite(computed[j])) return false;
            if (expected_dn[j] <= -1 && computed_dn[j] <= -1) {
                v = 0;
            } else if (expected_dn[j] >= 1 && computed_dn[j] >= 1) {
                v = 0;
            } else {
                v = computed_dn[j] - expected_dn[j];
            }
            //if (expected_dn[j] > computed_dn[j]) v *= 0.1;
            v = fabs(v);
//            if (v > 10) printf("Wanted %f, got %f\n", expected_dn[j], computed_dn[j]);
            if (v > max) max = v;
            sum += v*v;
        }
    }
    sum /= (data.numSamples() * data.nOuts());
    sse = sqrt(sum);
    cerr /= data.numSamples();

    avg_com /= data.numSamples();
    avg_exp /= data.numSamples();
    
    //delete [] computed_dn;
    //delete [] expected_dn;
    
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
    T e[1];
    for (i=0; i<data.numSamples(); i++) {
        T *s = data.getSample(i);
        T *o = fw(data.getIns(s), mem);
        T *d = data.getOuts(s);
        //if (d[0] > -0.85 && d[0] < 0.85) continue;
        if (d[0] < 0) {
            e[0] = -1;
        } else {
            e[0] = 1;
        }
        //double e = fabs(d[0] - o[0]);
        //if (e < 0.1) continue;
        //if (o[0] <= -1 && d[0] <= -1) continue;
        //if (o[0] >= 1 && d[0] >= 1) continue;
        // printf("s%d ", i);
        // for (int j=0; j<data.nOuts(); j++) {
        //     printf("%g ", o[j]);
        // }
        // printf("\n");
        //if (d[0] > o[0]) {
            //bk(d, mem, lr * 0.1);
        //} else {
        bk(e, mem, lr);
            //bk(d, mem, lr * e * e * e * e);
        //}
    }
}

template<typename T>
T find_learning_rate(T old_lr, DataSet<T>& data, DataSet<T>& val,
    T* mem,
    T *(*fw)(T *in, T *mem),
    void (*bk)(T *des, T *mem, T lr),
    long memsize)
{
    T *backup = (T*)malloc(memsize);
    bool up = false, did_up = false, did_down = false;
    T last_sse, sse, max, last_max, last_cerr;
    T r_down = 0.99;
    T r_up = 1.0 / r_down;
    bool good;
    
    compute_err(val, mem, fw, last_sse, last_max, last_cerr);

    int i = 0;
    while ((!did_up || !did_down) && i<10) {
        if (old_lr > 0.1) old_lr = 0.1;

        memcpy(backup, mem, memsize);
        sse = 1000000;
        max = 1000000;
        for (int j=0; j<10; j++) {
            training_epoch(data, backup, fw, bk, old_lr * 2.0f);
            T ssei, maxi, cerri;
            good = compute_err(val, backup, fw, ssei, maxi, cerri);
            //sse += ssei;
            //max += maxi;
            //if (ssei < sse) sse = ssei;
            //if (maxi < max) max = maxi;
            sse = ssei;
            max = maxi;
        }
        //sse /= 2;
        //max /= 2;
        
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
    
    DataSet<ValueType> data(39, 1), val(39,1);
    data.loadFile("xxiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiio", "ANN3_train.txt");
    val.loadFile("xxiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiio", "ANN3_val.txt");
    //data.dump();
    //data.normalize();
    //data.dump();
    
    ValueType *mem = allocate_39_64t_64t_1t();
    randomize_39_64t_64t_1t(mem);
    
    ValueType lr = 0.1;
    ValueType sse, max, cerr;
    ValueType best_sse = 1000000, best_max = 1000000, best_cerr = 1000000;
    
    signal(SIGINT, catch_sigint);
    
    compute_err(val, mem, forward_39_64t_64t_1t, sse, max, cerr);
    cout << lr << " " << sse << " " << max << " " << cerr << " " << endl;
    for (int i=0; i<1000000 && !global_quit; i++) {
        //lr = find_learning_rate(lr, data, val, mem, forward_39_64t_64t_1t, backward_39_64t_64t_1t, MEM_SIZE_39_64t_64t_1t);    
        lr = 0.1;
        if (i>10) lr = 0.01;
        if (i>20) lr = 0.001;
        for (int j=0; j<100; j++) {
            //printf("%d    \r", j);
            //fflush(stdout);
            training_epoch(data, mem, forward_39_64t_64t_1t, backward_39_64t_64t_1t, lr);
        }
        int ok = compute_err(val, mem, forward_39_64t_64t_1t, sse, max, cerr);
        if (!ok) break;
        cout << lr << " " << sse << " " << max << " " << cerr << " exp(" << min_exp << "," << avg_exp << "," << max_exp << ") com(" << min_com << "," << avg_com << "," << max_com << ")" << endl;
        
        if (/*sse < best_sse || max < best_max ||*/ cerr < best_cerr) {
            best_sse = sse;
            best_max = max;
            best_cerr = cerr;
            
            FILE *out = fopen("weights4_val.net", "wb");
            fwrite(mem, 1, MEM_SIZE_39_64t_64t_1t, out);
            fclose(out);
        }
    }
}
