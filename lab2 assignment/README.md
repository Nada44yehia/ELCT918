# CNN Assignment — LeNet-5, AlexNet, and VGG16


## How to Run

The notebook is designed to run in **Google Colab**.

1. Open the `.ipynb` notebook in Google Colab.
2. Run the notebook cells sequentially from the beginning.
3. The notebook automatically downloads the CIFAR-10 and CIFAR-100 datasets using Keras.
4. The notebook builds, trains, evaluates, and compares the three CNN architectures.
6. Training curves, accuracy results, loss values, top-1/top-5 accuracy, and epoch training time are generated in the notebook.

> **Note:** Training time may vary depending on the available Google Colab hardware (CPU/GPU) and runtime resources.

## Dependencies

The main Python libraries required are:

* Python
* TensorFlow / Keras
* NumPy
* Matplotlib
* Pandas

In Google Colab, these dependencies are generally pre-installed. If necessary, they can be installed using:

```python
!pip install tensorflow numpy matplotlib pandas
```

## Framework

The project uses:

* **TensorFlow**
* **Keras**

## Datasets

The following datasets are used:

* **CIFAR-10:** 50,000 training images and 10,000 test images across 10 classes.
* **CIFAR-100:** 50,000 training images and 10,000 test images across 100 classes.

Both datasets contain RGB images with a resolution of **32×32 pixels**.

## Models

The following CNN architectures are implemented:

* **LeNet-5**
* **AlexNet**
* **VGG16**

The implementations include minor adaptations required for the smaller CIFAR-10/CIFAR-100 input size and number of output classes.

## Results

The notebook generates:

* Training and validation loss curves
* Training and validation top-1 accuracy curves
* Training and validation top-5 accuracy curves
* Epoch training time
* Final evaluation results on the test dataset
* Comparison of model performance on CIFAR-10 and CIFAR-100

The generated results are presented directly in the notebook after training.
