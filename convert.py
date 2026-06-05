import os
import pandas as pd

# DATASET PATH
dataset_path = "school-supplies"

# CLASS NAMES
classes = [
    "Calculator",
    "Eraser",
    "Highlighter",
    "Pencil",
    "Whiteboard marker",
    "notebook"
]

# Convert function
def convert_csv_to_yolo(split):

    csv_path = os.path.join(dataset_path, split, "_annotations.csv")

    df = pd.read_csv(csv_path)

    labels_dir = os.path.join(dataset_path, split, "labels")

    os.makedirs(labels_dir, exist_ok=True)

    grouped = df.groupby("filename")

    for filename, group in grouped:

        txt_filename = filename.replace(".jpg", ".txt")

        txt_path = os.path.join(labels_dir, txt_filename)

        with open(txt_path, "w") as f:

            for _, row in group.iterrows():

                class_name = row["class"]

                if class_name not in classes:
                    continue

                class_id = classes.index(class_name)

                width = row["width"]
                height = row["height"]

                xmin = row["xmin"]
                ymin = row["ymin"]
                xmax = row["xmax"]
                ymax = row["ymax"]

                # Convert to YOLO format
                x_center = ((xmin + xmax) / 2) / width
                y_center = ((ymin + ymax) / 2) / height

                bbox_width = (xmax - xmin) / width
                bbox_height = (ymax - ymin) / height

                f.write(
                    f"{class_id} {x_center} {y_center} {bbox_width} {bbox_height}\n"
                )

# Convert all splits
convert_csv_to_yolo("train")
convert_csv_to_yolo("valid")
convert_csv_to_yolo("test")

print("Conversion Complete!")