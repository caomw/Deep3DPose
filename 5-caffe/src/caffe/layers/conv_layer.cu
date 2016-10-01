#include <vector>

#include "caffe/filler.hpp"
#include "caffe/layer.hpp"
#include "caffe/util/im2col.hpp"
#include "caffe/util/math_functions.hpp"
#include "caffe/vision_layers.hpp"

namespace caffe {

template<typename Dtype>
void ConvolutionLayer<Dtype>::Forward_gpu(const vector<Blob<Dtype>*>& bottom,
        const vector<Blob<Dtype>*>& top) {
    const Dtype* weight = this->blobs_[0]->gpu_data();
    for (int i = 0; i < bottom.size(); ++i) {
        const Dtype* bottom_data = bottom[i]->gpu_data();
        Dtype* top_data = top[i]->mutable_gpu_data();
        for (int n = 0; n < this->num_; ++n) {
            this->forward_gpu_gemm(bottom_data + bottom[i]->offset(n), weight,
                    top_data + top[i]->offset(n));
            if (this->bias_term_) {
                const Dtype* bias = this->blobs_[1]->gpu_data();
                this->forward_gpu_bias(top_data + top[i]->offset(n), bias);
            }
        }
    }
}

template<typename Dtype>
void ConvolutionLayer<Dtype>::Backward_gpu(const vector<Blob<Dtype>*>& top,
        const vector<bool>& propagate_down,
        const vector<Blob<Dtype>*>& bottom) {

    bool ispropagationweights = true;
    bool ispropagationdown = true;
    if (this->is_grl_train) {
        if (this->is_grl_layer == 2) {
            ispropagationweights = false;
            ispropagationdown = false;
            caffe_gpu_set(this->blobs_[0]->count(), Dtype(0),
                    this->blobs_[0]->mutable_gpu_diff());
            caffe_gpu_set(this->blobs_[1]->count(), Dtype(0),
                    this->blobs_[1]->mutable_gpu_diff());
            for (int i = 0; i < top.size(); ++i) {
                Dtype* bottom_diff = bottom[i]->mutable_gpu_diff();
                caffe_gpu_set(bottom[i]->count(), Dtype(0), bottom_diff);
            }
        }
    } else {
        if (this->is_grl_layer == 1) {
            ispropagationweights = false;
            ispropagationdown = true;
            caffe_gpu_set(this->blobs_[0]->count(), Dtype(0),
                    this->blobs_[0]->mutable_gpu_diff());
            caffe_gpu_set(this->blobs_[1]->count(), Dtype(0),
                    this->blobs_[1]->mutable_gpu_diff());
        }
    }

    const Dtype* weight = this->blobs_[0]->gpu_data();
    Dtype* weight_diff = this->blobs_[0]->mutable_gpu_diff();
    if (this->param_propagate_down_[0] && ispropagationweights) {
        caffe_gpu_set(this->blobs_[0]->count(), Dtype(0), weight_diff);
    }
    if (this->bias_term_ && this->param_propagate_down_[1]
            && ispropagationweights) {
        caffe_gpu_set(this->blobs_[1]->count(), Dtype(0),
                this->blobs_[1]->mutable_gpu_diff());
    }
    for (int i = 0; i < top.size(); ++i) {
        const Dtype* top_diff = top[i]->gpu_diff();
        // Bias gradient, if necessary.
        if (this->bias_term_ && this->param_propagate_down_[1]
                && ispropagationweights) {
            Dtype* bias_diff = this->blobs_[1]->mutable_gpu_diff();
            for (int n = 0; n < this->num_; ++n) {
                this->backward_gpu_bias(bias_diff,
                        top_diff + top[i]->offset(n));
            }
        }
        if (this->param_propagate_down_[0] || propagate_down[i]) {
            const Dtype* bottom_data = bottom[i]->gpu_data();
            Dtype* bottom_diff = bottom[i]->mutable_gpu_diff();
            for (int n = 0; n < this->num_; ++n) {
                // gradient w.r.t. weight. Note that we will accumulate diffs.
                if (this->param_propagate_down_[0] && ispropagationweights) {
                    this->weight_gpu_gemm(bottom_data + bottom[i]->offset(n),
                            top_diff + top[i]->offset(n), weight_diff);
                }
                // gradient w.r.t. bottom data, if necessary.
                if (propagate_down[i] && ispropagationdown) {
                    this->backward_gpu_gemm(top_diff + top[i]->offset(n),
                            weight, bottom_diff + bottom[i]->offset(n));
                }
            }
        }
    }
}

INSTANTIATE_LAYER_GPU_FUNCS(ConvolutionLayer);

} // namespace caffe