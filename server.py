import cv2
import numpy as np
import json
import torch
import mediapipe as mp
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from ultralytics import YOLO

app = FastAPI(title="AI Object Detection WebSocket Server")

# Allow CORS for web clients if needed
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# -----------------------------------
# LOAD YOLO MODEL (Dynamic Device selection)
# -----------------------------------
device = 0 if torch.cuda.is_available() else "cpu"
print(f"Loading YOLOv8 model on device: {device}")
model = YOLO("yolov8s.pt")

# -----------------------------------
# MEDIAPIPE HAND TRACKING (Tasks API)
# -----------------------------------
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision as mp_vision

base_options = mp_python.BaseOptions(model_asset_path='hand_landmarker.task')
options = mp_vision.HandLandmarkerOptions(
    base_options=base_options,
    num_hands=2,
    min_hand_detection_confidence=0.7,
    min_hand_presence_confidence=0.7
)
detector = mp_vision.HandLandmarker.create_from_options(options)

# Educational objects list to filter YOLO detections
educational_objects = [
    "book",
    "cell phone",
    "keyboard",
    "mouse",
    "remote"
]

@app.get("/")
def read_root():
    return {"status": "running", "device": str(device)}

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    print("Client connected via WebSocket")
    try:
        while True:
            # Receive image bytes from client
            data = await websocket.receive_bytes()
            
            # Decode JPEG image
            nparr = np.frombuffer(data, np.uint8)
            frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            if frame is None:
                continue

            # Run YOLO Object Detection & Tracking
            results = model.track(
                frame,
                persist=True,
                conf=0.5,
                device=device,
                verbose=False
            )

            detected_objects = []
            for result in results:
                boxes = result.boxes
                for box in boxes:
                    class_id = int(box.cls[0])
                    class_name = model.names[class_id]

                    # Filter for educational objects
                    if class_name not in educational_objects:
                        continue

                    track_id = int(box.id[0]) if box.id is not None else 0
                    x1, y1, x2, y2 = map(int, box.xyxy[0])
                    
                    detected_objects.append({
                        "class": class_name,
                        "id": track_id,
                        "box": [x1, y1, x2, y2]
                    })

            # Run MediaPipe Hand Tracking
            rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb_frame)
            hand_results = detector.detect(mp_image)

            detected_hands = []
            if hand_results.hand_landmarks:
                for hand_landmarks in hand_results.hand_landmarks:
                    # Capture all 21 hand landmarks
                    landmarks_list = []
                    for lm in hand_landmarks:
                        landmarks_list.append({
                            "x": lm.x,
                            "y": lm.y,
                            "z": lm.z
                        })
                    
                    # Store fingertip (landmark 8) for easy client reference
                    if len(hand_landmarks) > 8:
                        fingertip = hand_landmarks[8]
                        detected_hands.append({
                            "fingertip": {"x": fingertip.x, "y": fingertip.y},
                            "landmarks": landmarks_list
                        })

            # Return detection results as JSON
            response_data = {
                "objects": detected_objects,
                "hands": detected_hands
            }
            await websocket.send_text(json.dumps(response_data))

    except WebSocketDisconnect:
        print("Client disconnected")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
