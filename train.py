from ultralytics import YOLO
import torch

def main():
    device = 0 if torch.cuda.is_available() else "cpu"
    print("CUDA Available:", torch.cuda.is_available())
    if torch.cuda.is_available():
        print("Using GPU:", torch.cuda.get_device_name(0))
    else:
        print("Using CPU")

    model = YOLO("yolov8s.pt")

    model.train(
        data="school-supplies/data.yaml",
        epochs=50,
        imgsz=640,
        batch=8,
        device=device,
        workers=0
    )

if __name__ == "__main__":
    main()