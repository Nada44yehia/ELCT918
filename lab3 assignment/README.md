# ELCT 918 -- Lab Assignment 3

## Real-Time Handwritten Digit Recognition

This project implements a real-time handwritten digit recognition system
using **LeNet-5**, MNIST preprocessing, and OpenCV.

The project is divided into training/preprocessing notebooks and local
real-time inference scripts.

## Project Files

``` text
Lab3 assignment/
│
├── ELCT918_Lab3.ipynb
├── Arabic_part.ipynb
├── lenet5_mnist.keras
├── arabic_lenet5.keras.zip
├── task3.py
└── task3_arabic.py
```

### Main files

-   **`ELCT918_Lab3.ipynb`**\
    Main notebook for the MNIST part of the assignment. It is run using
    **Google Colab** and contains the model training and preprocessing
    work.

-   **`lenet5_mnist.keras`**\
    Trained MNIST LeNet-5 model used for inference.

-   **`task3.py`**\
    Real-time MNIST handwritten digit recognition application. It is run
    **locally on the laptop using Visual Studio Code** because it needs
    access to the laptop webcam.

-   **`Arabic_part.ipynb`**\
    Notebook for the optional Arabic-Indic digit part. It is run using
    **Google Colab**.

-   **`arabic_lenet5.keras.zip`**\
    Trained model for the Arabic-Indic digit recognition part.

-   **`task3_arabic.py`**\
    Local real-time application for Arabic-Indic digit recognition. It
    is run using **Visual Studio Code**.

## 1. Environment

### Google Colab

The notebooks are run in Google Colab.

The training part can use the Colab GPU. The trained model is then saved
and downloaded to the laptop for the real-time application.

### Local computer

The real-time scripts are run locally because Google Colab cannot
directly access the laptop webcam.

Install the required Python packages from the Visual Studio Code
terminal:

``` bash
python -m pip install tensorflow opencv-python numpy matplotlib
```

## 2. Running the MNIST Notebook

Open:

``` text
ELCT918_Lab3.ipynb
```

in **Google Colab**.

Run the notebook cells to:

1.  Load and prepare the MNIST dataset.
2.  Adapt LeNet-5 for MNIST.
3.  Train the model.
4.  Evaluate the model.
5.  Save the trained model.
6.  Implement and test the preprocessing pipeline.

The MNIST images are converted to the format expected by LeNet-5. The
28×28 images are padded to 32×32.

The same normalization used during training must also be used during
inference.

For this implementation:

``` text
Mean = 0.1307
Standard deviation = 0.3081
```

## 3. Task 2 -- Image Preprocessing

The preprocessing pipeline converts a handwritten digit from a
camera/image ROI into an MNIST-like input.

The main steps are:

1.  Convert the image to grayscale.
2.  Apply Gaussian blur.
3.  Threshold and invert the image using Otsu thresholding.
4.  Apply dilation when needed to strengthen thin strokes.
5.  Find the largest digit contour.
6.  Crop the digit.
7.  Resize the larger dimension to 20 pixels while preserving the aspect
    ratio.
8.  Center the digit in a 28×28 image.
9.  Pad it to 32×32.
10. Scale the pixel values to `[0, 1]`.
11. Apply the MNIST mean and standard deviation normalization.
12. Add the required batch/channel dimensions before inference.

## 4. Running the MNIST Real-Time Application

After downloading the trained model, place it in the same folder as
`task3.py`.

The folder should look like:

``` text
Lab3 assignment/
│
├── task3.py
└── lenet5_mnist.keras
```

Open the folder in **Visual Studio Code**.

Open the VS Code terminal and run:

``` bash
python task3.py
```

The application opens the camera and displays:

-   The camera frame.
-   A square region where the digit should be written.
-   The predicted digit.
-   The prediction confidence.
-   The current FPS.
-   An enlarged view of the model input.

Press:

``` text
q
```

to exit.

### Camera

A laptop webcam can be used directly.

If the camera is not detected, try changing the camera index in
`task3.py`, for example:

``` python
cv2.VideoCapture(0)
```

to:

``` python
cv2.VideoCapture(1)
```

or:

``` python
cv2.VideoCapture(2)
```

A phone can also be used as a webcam through a suitable application like droidcam


## 5. Arabic-Indic Digit Bonus

The optional Arabic-Indic part uses the Arabic handwritten digit dataset
and a separate LeNet-5 model.

The notebook:

``` text
Arabic_part.ipynb
```

is run in **Google Colab**.

The real-time application:

``` text
task3_arabic.py
```

is run locally in **Visual Studio Code**.

The trained Arabic model is provided as:

``` text
arabic_lenet5.keras.zip
```

Extract the model before running the Arabic real-time application, and
make sure the path used in `task3_arabic.py` matches the extracted model
location.

The Arabic-Indic digits include:

``` text
٠ ١ ٢ ٣ ٤ ٥ ٦ ٧ ٨ ٩
```


