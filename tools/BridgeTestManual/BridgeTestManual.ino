void setup() {
  Serial.begin(115200);
  Serial1.begin(115200);
}

void loop() {
  Serial.println("MCU Serial alive");
  Serial1.println("MCU Serial1 alive");
  delay(1000);
}
