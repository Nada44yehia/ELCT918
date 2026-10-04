# ============================================================
# TASK 3 — REAL-TIME HANDWRITTEN DIGIT RECOGNITION
# ============================================================

import cv2
import numpy as np
import tensorflow as tf
import time


# ============================================================
# 1. Load trained LeNet-5 model
# ============================================================

import os

class TrainableSubsampling(tf.keras.layers.Layer):

    def build(self, input_shape):

        channels = input_shape[-1]

        # One trainable coefficient per feature map
        self.alpha = self.add_weight(
            name="alpha",
            shape=(channels,),
            initializer="ones",
            trainable=True
        )

        # One trainable bias per feature map
        self.beta = self.add_weight(
            name="beta",
            shape=(channels,),
            initializer="zeros",
            trainable=True
        )

    def call(self, inputs):

        # Average over non-overlapping 2x2 regions
        x = tf.nn.avg_pool2d(
            inputs,
            ksize=2,
            strides=2,
            padding="VALID"
        )

        # Convert average into sum
        x = x * 4.0

        # Trainable scaling and bias
        x = x * self.alpha + self.beta

        # LeNet-style subsampling activation
        return tf.nn.sigmoid(x)

print("TrainableSubsampling layer defined successfully.")

# Get the directory where this python script is located
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_PATH = os.path.join(BASE_DIR, "lenet5_mnist.keras")

model = tf.keras.models.load_model(
    MODEL_PATH,
    custom_objects={
        "TrainableSubsampling": TrainableSubsampling
    }
)

print("Model loaded successfully.")


# ============================================================
# 2. MNIST normalization
# ============================================================
# MUST be exactly the same values used in Task 1

MNIST_MEAN = 0.1307
MNIST_STD = 0.3081


# ============================================================
# 3. Preprocessing function
# ============================================================

def preprocess(roi):

    # --------------------------------------------------------
    # STEP 1 — Grayscale + Gaussian blur
    # --------------------------------------------------------

    gray = cv2.cvtColor(
        roi,
        cv2.COLOR_BGR2GRAY
    )

    blurred = cv2.GaussianBlur(
        gray,
        (5, 5),
        0
    )


    # --------------------------------------------------------
    # STEP 2 — Threshold + invert
    # --------------------------------------------------------

    _, thresholded = cv2.threshold(
        blurred,
        0,
        255,
        cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU
    )


    # Optional dilation
    kernel = np.ones(
        (2, 2),
        np.uint8
    )

    thresholded = cv2.dilate(
        thresholded,
        kernel,
        iterations=1
    )


    # --------------------------------------------------------
    # STEP 3 — Find digit contour
    # --------------------------------------------------------

    contours, _ = cv2.findContours(
        thresholded,
        cv2.RETR_EXTERNAL,
        cv2.CHAIN_APPROX_SIMPLE
    )


    # No contour found
    if len(contours) == 0:

        blank = np.zeros(
            (32, 32),
            dtype=np.uint8
        )

        normalized = (
            blank.astype(np.float32) / 255.0
        )

        normalized = (
            normalized - MNIST_MEAN
        ) / MNIST_STD

        tensor = normalized.reshape(
            1, 32, 32, 1
        )

        return tensor, np.zeros(
            (28, 28),
            dtype=np.uint8
        )


    # Largest contour
    largest_contour = max(
        contours,
        key=cv2.contourArea
    )


    x, y, w, h = cv2.boundingRect(
        largest_contour
    )


    cropped = thresholded[
        y:y+h,
        x:x+w
    ]


    # --------------------------------------------------------
    # STEP 4 — Resize to 20 pixels
    # --------------------------------------------------------

    scale = 20.0 / max(w, h)

    new_w = max(
        1,
        int(round(w * scale))
    )

    new_h = max(
        1,
        int(round(h * scale))
    )


    resized = cv2.resize(
        cropped,
        (new_w, new_h),
        interpolation=cv2.INTER_AREA
    )


    # --------------------------------------------------------
    # Center in 28x28
    # --------------------------------------------------------

    centered = np.zeros(
        (28, 28),
        dtype=np.uint8
    )


    start_x = (28 - new_w) // 2
    start_y = (28 - new_h) // 2


    centered[
        start_y:start_y + new_h,
        start_x:start_x + new_w
    ] = resized


    # --------------------------------------------------------
    # Pad 28x28 -> 32x32
    # --------------------------------------------------------

    padded = np.pad(
        centered,
        ((2, 2), (2, 2)),
        mode="constant",
        constant_values=0
    )


    # --------------------------------------------------------
    # STEP 5 — Normalize
    # --------------------------------------------------------

    normalized = (
        padded.astype(np.float32) / 255.0
    )


    normalized = (
        normalized - MNIST_MEAN
    ) / MNIST_STD


    # Add channel dimension
    tensor = np.expand_dims(
        normalized,
        axis=-1
    )


    # Add batch dimension
    tensor = np.expand_dims(
        tensor,
        axis=0
    )


    # Return:
    # tensor = input for LeNet
    # centered = 28x28 model view

    return tensor, centered


# ============================================================
# 4. Open webcam
# ============================================================

cap = cv2.VideoCapture(1)


# Check camera
if not cap.isOpened():

    raise RuntimeError(
        "Could not open camera."
    )


print("Camera opened successfully.")
print("Press 'q' to quit.")


# ============================================================
# 5. FPS variables
# ============================================================

prev_time = time.time()


# ============================================================
# 6. Real-time loop
# ============================================================

while True:

    # --------------------------------------------------------
    # Read frame
    # --------------------------------------------------------

    ret, frame = cap.read()


    if not ret:

        print("Could not read frame.")
        break


    # --------------------------------------------------------
    # Flip image horizontally
    # --------------------------------------------------------
    # Makes the webcam behave like a mirror.

    frame = cv2.flip(
        frame,
        1
    )


    # Get frame dimensions

    height, width = frame.shape[:2]


    # --------------------------------------------------------
    # Create center square
    # --------------------------------------------------------

    box_size = 300

    x1 = (width - box_size) // 2
    y1 = (height - box_size) // 2

    x2 = x1 + box_size
    y2 = y1 + box_size


    # Draw square

    cv2.rectangle(
        frame,
        (x1, y1),
        (x2, y2),
        (0, 255, 0),
        2
    )


    # --------------------------------------------------------
    # Crop ROI
    # --------------------------------------------------------

    roi = frame[
        y1:y2,
        x1:x2
    ]


    # --------------------------------------------------------
    # Preprocess ROI
    # --------------------------------------------------------

    tensor, model_view = preprocess(
        roi
    )


    # --------------------------------------------------------
    # Run LeNet prediction
    # --------------------------------------------------------

    prediction = model.predict(
        tensor,
        verbose=0
    )


    # Get predicted digit

    predicted_digit = np.argmax(
        prediction[0]
    )


    # Get confidence

    confidence = np.max(
        prediction[0]
    )


    # --------------------------------------------------------
    # Calculate FPS
    # --------------------------------------------------------

    current_time = time.time()

    fps = 1.0 / (
        current_time - prev_time
    )

    prev_time = current_time


    # --------------------------------------------------------
    # Display prediction
    # --------------------------------------------------------

    text_prediction = (
        f"Digit: {predicted_digit}"
    )

    text_confidence = (
        f"Confidence: "
        f"{confidence * 100:.2f}%"
    )

    text_fps = (
        f"FPS: {fps:.1f}"
    )


    cv2.putText(
        frame,
        text_prediction,
        (20, 40),
        cv2.FONT_HERSHEY_SIMPLEX,
        1,
        (0, 255, 0),
        2
    )


    cv2.putText(
        frame,
        text_confidence,
        (20, 80),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.8,
        (0, 255, 0),
        2
    )


    cv2.putText(
        frame,
        text_fps,
        (20, 120),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.8,
        (0, 255, 0),
        2
    )


    # --------------------------------------------------------
    # Display camera window
    # --------------------------------------------------------

    cv2.imshow(
        "Real-Time Digit Recognition",
        frame
    )


    # --------------------------------------------------------
    # Display model's 28x28 view
    # --------------------------------------------------------

    model_view_large = cv2.resize(
        model_view,
        (280, 280),
        interpolation=cv2.INTER_NEAREST
    )


    cv2.imshow(
        "Model View (28x28)",
        model_view_large
    )


    # --------------------------------------------------------
    # Press q to quit
    # --------------------------------------------------------

    key = cv2.waitKey(1) & 0xFF

    if key == ord("q"):
        break


# ============================================================
# 7. Release camera
# ============================================================

cap.release()

cv2.destroyAllWindows()

print("Program ended.")
