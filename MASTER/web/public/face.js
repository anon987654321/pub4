"use strict";

const FACE_PARTS = [
  "face.part1.txt",
  "face.part2.txt",
  "face.part3.txt",
  "face.part4.txt",
  "face.part5.txt"
];

const FACE_BASE = new URL(import.meta.url);
const FACE_TEXT = await Promise.all(FACE_PARTS.map(async (part) => {
  const res = await fetch(new URL(part, FACE_BASE));
  if (!res.ok) throw new Error(`failed to load ${part}: ${res.status}`);
  return res.text();
}));

const FACE_BLOB = new Blob([FACE_TEXT.join("\n")], { type: "text/javascript" });
const FACE_BLOB_URL = URL.createObjectURL(FACE_BLOB);
try {
  await import(FACE_BLOB_URL);
} finally {
  URL.revokeObjectURL(FACE_BLOB_URL);
}
