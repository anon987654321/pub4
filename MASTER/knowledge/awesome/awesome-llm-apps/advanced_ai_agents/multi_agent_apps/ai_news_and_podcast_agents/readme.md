git clone https://github.com/arun477/beifong.git && cd beifong
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
python -m playwright install
python bootstrap_demo.py   # optional sample data
