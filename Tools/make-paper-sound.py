import wave,random,math,struct
from pathlib import Path
rng=random.Random(731);rate=24000;duration=.24;previous=0;samples=[]
for i in range(int(rate*duration)):
 t=i/rate;noise=rng.uniform(-1,1);high=noise-previous*.7;previous=noise
 env=math.sin(math.pi*t/duration)**2*(.35+.65*abs(math.sin(t*math.pi*42)))
 samples.append(int(max(-1,min(1,high*env*.28))*32767))
path=Path(__file__).resolve().parent.parent/'Resources/paper-rustle.wav'
with wave.open(str(path),'wb') as w:w.setnchannels(1);w.setsampwidth(2);w.setframerate(rate);w.writeframes(struct.pack('<'+'h'*len(samples),*samples))
