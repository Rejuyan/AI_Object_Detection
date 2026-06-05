from ultralytics import YOLO
import mediapipe as mp
import cv2
import time
import torch

# -----------------------------------
# LOAD YOLO MODEL (Dynamic Device selection)
# -----------------------------------
device = 0 if torch.cuda.is_available() else "cpu"
model = YOLO("yolov8s.pt")

# -----------------------------------
# MEDIAPIPE HAND TRACKING
# -----------------------------------
mp_hands = mp.solutions.hands
mp_draw = mp.solutions.drawing_utils

hands = mp_hands.Hands(
    static_image_mode=False,
    max_num_hands=2,
    min_detection_confidence=0.7,
    min_tracking_confidence=0.7
)

# -----------------------------------
# EDUCATIONAL OBJECTS ONLY
# -----------------------------------
educational_objects = [
    "book",
    "cell phone",
    "keyboard",
    "mouse",
    "remote"
]

# -----------------------------------
# OPEN WEBCAM
# -----------------------------------
cap = cv2.VideoCapture(0)
if not cap.isOpened():
    print("Error: Could not open webcam. Please check connection or if another app is using it.")
    exit(1)

cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)

prev_time = 0

while True:
    success, frame = cap.read()
    if not success:
        print("Error: Failed to read frame from webcam.")
        break

    # Mirror effect
    frame = cv2.flip(frame, 1)

    # -----------------------------------
    # YOLO OBJECT DETECTION
    # -----------------------------------
    results = model.track(
        frame,
        persist=True,
        conf=0.5,
        device=device,
        verbose=False
    )

    # Process detections
    for result in results:
        boxes = result.boxes
        for box in boxes:
            # Coordinates
            x1, y1, x2, y2 = map(int, box.xyxy[0])

            # Class info
            class_id = int(box.cls[0])
            class_name = model.names[class_id]

            # Ignore non-educational objects
            if class_name not in educational_objects:
                continue

            # Tracking ID
            track_id = f"#{int(box.id[0])}" if box.id is not None else ""
            label = f"{class_name} {track_id}".strip()

            # Draw rectangle
            cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 255, 0), 2)

            # Draw label background dynamically sized based on text
            (text_width, text_height), baseline = cv2.getTextSize(
                label, cv2.FONT_HERSHEY_SIMPLEX, 0.6, 2
            )
            
            # Ensure text is not drawn off the top edge
            y_label = max(y1, text_height + 15)
            
            cv2.rectangle(
                frame,
                (x1, y_label - text_height - 10),
                (x1 + text_width + 10, y_label + baseline - 5),
                (0, 120, 0),
                -1
            )

            # Draw label text
            cv2.putText(
                frame,
                label,
                (x1 + 5, y_label - 5),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.6,
                (255, 255, 255),
                2
            )

    # -----------------------------------
    # HAND TRACKING
    # -----------------------------------
    rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    hand_results = hands.process(rgb_frame)

    if hand_results.multi_hand_landmarks:
        for hand_landmarks in hand_results.multi_hand_landmarks:
            mp_draw.draw_landmarks(
                frame,
                hand_landmarks,
                mp_hands.HAND_CONNECTIONS
            )

            # Index fingertip
            fingertip = hand_landmarks.landmark[8]
            h, w, c = frame.shape
            x = int(fingertip.x * w)
            y = int(fingertip.y * h)

            # Draw fingertip
            cv2.circle(frame, (x, y), 10, (0, 0, 255), -1)

    # -----------------------------------
    # FPS COUNTER
    # -----------------------------------
    current_time = time.time()
    fps = 1 / (current_time - prev_time) if (current_time - prev_time) > 0 else 0
    prev_time = current_time

    cv2.putText(
        frame,
        f"FPS: {int(fps)}",
        (20, 40),
        cv2.FONT_HERSHEY_SIMPLEX,
        1,
        (0, 255, 255),
        2
    )

    # System title
    cv2.putText(
        frame,
        "Educational Smart Detector",
        (20, 80),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.8,
        (255, 255, 0),
        2
    )

    # -----------------------------------
    # SHOW OUTPUT
    # -----------------------------------
    cv2.imshow("Educational Smart Detector", frame)

    # Quit
    if cv2.waitKey(1) & 0xFF == ord("q"):
        break

# Cleanup
cap.release()
cv2.destroyAllWindows()