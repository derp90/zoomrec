import csv
import logging
import os
import psutil
import pyautogui
import schedule
import signal
import subprocess
import threading
import time
import atexit
import requests
import cv2
import numpy as np
from datetime import datetime, timedelta
import secrets
from functools import partial

# ---------------- Logging -----------------
logging.basicConfig(format='%(asctime)s %(levelname)s %(message)s', level=logging.INFO)

DEBUG = True if os.getenv('DEBUG') == 'True' else False
pyautogui.FAILSAFE = False

# ---------------- Paths & Variables -----------------
BASE_PATH = os.getenv('HOME')
CSV_PATH = os.path.join(BASE_PATH, "meetings.csv")
IMG_PATH = os.path.join(BASE_PATH, "img")
REC_PATH = os.path.join(BASE_PATH, "recordings")
AUDIO_PATH = os.path.join(BASE_PATH, "audio")
DEBUG_PATH = os.path.join(REC_PATH, "screenshots")
os.environ.pop("QT_PLUGIN_PATH", None)
os.environ.pop("QT_QPA_PLATFORM_PLUGIN_PATH", None)
os.environ["QT_QPA_PLATFORM"] = "xcb"
os.environ["QT_PLUGIN_PATH"] = "/opt/zoom/plugins"
os.environ["LD_LIBRARY_PATH"] = "/opt/zoom"
scheduled_meetings = set()
csv_last_load = None
CSV_RELOAD_SECONDS = 60  # reload CSV every minute

TELEGRAM_TOKEN = os.getenv('TELEGRAM_BOT_TOKEN')
TELEGRAM_CHAT_ID = os.getenv('TELEGRAM_CHAT_ID')
TELEGRAM_RETRIES = 5

DISPLAY_NAME = os.getenv('DISPLAY_NAME')
if DISPLAY_NAME is None or len(DISPLAY_NAME) < 3:
    NAME_LIST = ['iPhone', 'iPad', 'Macbook', 'Desktop', 'Huawei', 'Mobile', 'PC', 'Windows', 'Home', 'MyPC', 'Computer', 'Android']
    DISPLAY_NAME = secrets.SystemRandom().choice(NAME_LIST)

TIME_FORMAT = "%Y-%m-%d_%H-%M-%S"
CSV_DELIMITER = ';'

ONGOING_MEETING = False
VIDEO_PANEL_HIDED = False

# ---------------- OpenCV Functions -----------------
def grab_screenshot():
    """Take a screenshot as a numpy array (BGR) for OpenCV"""
    screenshot = pyautogui.screenshot()
    img = cv2.cvtColor(np.array(screenshot), cv2.COLOR_RGB2BGR)
    return img

def locate_image_on_screen(image_name, threshold=0.9):
    """Return the center coordinates (x, y) if the template matches the screen"""
    img_path = os.path.join(IMG_PATH, image_name)
    if not os.path.exists(img_path):
        logging.error(f"Image not found: {img_path}")
        return None

    template = cv2.imread(img_path)
    screenshot = grab_screenshot()
    res = cv2.matchTemplate(screenshot, template, cv2.TM_CCOEFF_NORMED)
    min_val, max_val, min_loc, max_loc = cv2.minMaxLoc(res)

    if max_val >= threshold:
        template_h, template_w = template.shape[:2]
        center_x = max_loc[0] + template_w // 2
        center_y = max_loc[1] + template_h // 2
        return (center_x, center_y)
    else:
        if DEBUG:
            logging.warning(f"Template '{image_name}' not found (confidence={max_val:.2f})")
        return None

def image_exists(image_name, threshold=0.9):
    return locate_image_on_screen(image_name, threshold) is not None

# ---------------- Helper Functions -----------------
def send_telegram_message(text):
    global TELEGRAM_TOKEN, TELEGRAM_CHAT_ID, TELEGRAM_RETRIES
    if not TELEGRAM_TOKEN or not TELEGRAM_CHAT_ID:
        logging.error("Telegram credentials missing. Cannot send messages.")
        return

    url_req = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage?chat_id={TELEGRAM_CHAT_ID}&text={text}"
    tries = 0
    done = False
    while not done:
        try:
            res = requests.get(url_req).json()
            done = res.get('ok', False)
        except Exception:
            done = False
        tries += 1
        if not done and tries < TELEGRAM_RETRIES:
            logging.error(f"Telegram message failed. Retry {tries} in 5s...")
            time.sleep(5)
        if not done and tries >= TELEGRAM_RETRIES:
            logging.error("Telegram message failed multiple times. Check credentials.")
            done = True

def find_process_id_by_name(process_name):
    procs = []
    for proc in psutil.process_iter(attrs=['pid', 'name']):
        try:
            if process_name.lower() in proc.info['name'].lower():
                procs.append(proc.info)
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
            continue
    return procs

def exit_process_by_name(name):
    pids = find_process_id_by_name(name)
    if pids:
        logging.info(f"Killing {name} process(es)...")
        for p in pids:
            try:
                os.kill(p['pid'], signal.SIGKILL)
            except Exception as ex:
                logging.error(f"Could not terminate {name}[{p['pid']}]: {ex}")
                
def _cleanup_when_zoom_exits(pid, meet_id, poll_interval=1):
    """Background waiter that removes meet_id from active_meetings after Zoom process ends."""
    try:
        proc = psutil.Process(pid)
        proc.wait()  # blocks until process exits
    except Exception:
        # fallback: poll until pid disappears
        while psutil.pid_exists(pid):
            time.sleep(poll_interval)
    finally:
        if meet_id in active_meetings:
            active_meetings.discard(meet_id)
            logging.info(f"🧹 Meeting {meet_id} ended — removed from active registry.")


def show_toolbars():
    width, height = pyautogui.size()
    y = height // 2
    pyautogui.moveTo(0, y, duration=0.5)
    pyautogui.moveTo(width - 1, y, duration=0.5)

# ---------------- Audio & Mute -----------------
def join_audio(description):
    pos = locate_image_on_screen('join_with_computer_audio.png')
    if pos:
        pyautogui.click(*pos)
        logging.info("Joined with computer audio.")
        return True
    else:
        logging.error("Could not join with computer audio!")
        return False

def mute(description):
    pos = locate_image_on_screen('mute.png')
    if pos:
        show_toolbars()
        pyautogui.click(*pos)
        return True
    return False

def unmute(description):
    pos = locate_image_on_screen('unmute.png')
    if pos:
        show_toolbars()
        pyautogui.click(*pos)
        return True
    return False

def play_audio(description):
    if not os.path.exists(AUDIO_PATH):
        logging.error("Audio path does not exist!")
        return
    files = [f for f in os.listdir(AUDIO_PATH) if f.endswith(".wav")]
    if not files:
        logging.error("No .wav files found!")
        return
    unmute(description)
    file = secrets.SystemRandom().choice(files)
    path = os.path.join(AUDIO_PATH, file)
    subprocess.run(f"/usr/bin/paplay --device=microphone -p {path}", shell=True)
    mute(description)

# ---------------- Background Threads -----------------
class BackgroundThread(threading.Thread):
    def __init__(self, interval=10):
        self.interval = interval
        threading.Thread.__init__(self, daemon=True)
        self.start()

    def run(self):
        global ONGOING_MEETING
        ONGOING_MEETING = True
        while ONGOING_MEETING:
            if image_exists('meeting_is_being_recorded.png'):
                logging.info("Meeting is being recorded.")
                pos = locate_image_on_screen('got_it.png')
                if pos: pyautogui.click(*pos)
            if image_exists('meeting_ended_by_host_1.png') or image_exists('meeting_ended_by_host_2.png'):
                logging.info("Meeting ended by host.")
                ONGOING_MEETING = False
            time.sleep(self.interval)

class HideViewOptionsThread(threading.Thread):
    def __init__(self, interval=10):
        self.interval = interval
        threading.Thread.__init__(self, daemon=True)
        self.start()

    def run(self):
        global VIDEO_PANEL_HIDED
        while ONGOING_MEETING:
            pos = locate_image_on_screen('view_options.png')
            if pos and not VIDEO_PANEL_HIDED:
                pyautogui.click(*pos)
                if image_exists('hide_video_panel.png'):
                    pyautogui.click(*locate_image_on_screen('hide_video_panel.png'))
                    VIDEO_PANEL_HIDED = True
            time.sleep(self.interval)

# ---------------- Join Meeting -----------------
def join(meet_id, meet_pw, duration, description):
    global VIDEO_PANEL_HIDED
    logging.info(f"Joining meeting: {description}")

    # Guard: avoid double-join for same meeting id
    if meet_id in active_meetings:
        logging.info(f"🚫 Already handling meeting {meet_id}; skipping duplicate join.")
        return

    # Kill existing zoom instances (so we start a fresh one)
    exit_process_by_name("zoom")

    join_by_url = meet_id.startswith("http") or meet_id.startswith("zoommtg://")

    if join_by_url:
        cmd = ["/usr/bin/zoom", f"--url={meet_id}"]
    else:
        cmd = ["/usr/bin/zoom"]

    env = os.environ.copy()
    env["DISPLAY"] = ":1"

    # Launch Zoom
    zoom_proc = subprocess.Popen(cmd, env=env, preexec_fn=os.setsid)

    # Register as active immediately (prevents racing duplicates)
    active_meetings.add(meet_id)
    logging.info(f"🔒 Registered meeting {meet_id} as active. active_meetings={active_meetings}")

    # Start cleanup thread to remove active flag when Zoom exits
    t = threading.Thread(target=_cleanup_when_zoom_exits, args=(zoom_proc.pid, meet_id), daemon=True)
    t.start()

    # Wait for Zoom to start
    img_name = 'join.png' if join_by_url else 'join_meeting.png'
    while not locate_image_on_screen(img_name):
        logging.info("Waiting for Zoom to be ready...")
        time.sleep(1)

    pos = locate_image_on_screen('join.png')
    if pos:
        pyautogui.click(*pos)
        time.sleep(5)
        
    # Enter meeting credentials and join
    if not join_by_url:
        pyautogui.press(['tab','tab'])
        pyautogui.write(meet_id, interval=0.1)
        pyautogui.press(['tab','tab'])
        pyautogui.hotkey('ctrl','a')
        pyautogui.write(DISPLAY_NAME, interval=0.1)
        pyautogui.press(['tab','space','tab','tab','space','tab','tab','space'])
    else:
        pyautogui.hotkey('ctrl','a')
        pyautogui.write(DISPLAY_NAME, interval=0.1)
#        pyautogui.press(['tab','space','tab','tab','space','tab','tab','space'])

#    time.sleep(2)
#    pos = locate_image_on_screen('join_meeting_password.png')
#    if pos:
#        pyautogui.click(*pos)
#        pyautogui.write(meet_pw)
#        pyautogui.press('enter')

    time.sleep(5)
    join_audio(description)

    # Start background threads
    BackgroundThread()
    HideViewOptionsThread()

    # Optional Telegram notification
    send_telegram_message(f"Meeting joined: {description}")

# ---------------- Schedule -----------------
def join_if_correct_date(meet_id, meet_pw, meet_duration, meet_description, meet_date):
    today = datetime.now().date()
    logging.info(f"📅 Comparing meeting date {meet_date.date()} vs today {today}")

    # Guard: if already active, skip
    if meet_id in active_meetings:
        logging.info(f"🚫 Meeting {meet_id} already active; skipping duplicate join.")
        return

    if meet_date.date() == today:
        logging.info(f"✅ Date match for {meet_id}, joining meeting")
        join(meet_id, meet_pw, meet_duration, meet_description)
    else:
        logging.info(f"⏭️ Skipping {meet_id}, date does not match ({meet_date.date()} != {today})")


def join_ongoing_meetings(meetings):
    """Join all meetings currently in progress (catch-up mode)."""
    now = datetime.now()
    for m in meetings:
        start_time = m["datetime"]
        end_time = start_time + timedelta(seconds=m["duration"] + 600)

        if start_time <= now <= end_time:
            logging.info(f"⚡ Catch-up: '{m['desc']}' meeting already in progress → joining now")
            join(m["id"], m["pw"], m["duration"], m["desc"])

def load_meetings_from_csv():
    """Load meetings from CSV file and return structured list."""
    meetings = []

    with open(CSV_PATH, mode="r") as f:
        csv_reader = csv.DictReader(f, delimiter=CSV_DELIMITER)
        for row in csv_reader:
            if str(row.get("record", "false")).lower() != "true":
                continue

            meet_date = datetime.strptime(row["date"], "%d/%m/%Y")
            meet_time = datetime.strptime(row["time"], "%H:%M").time()
            start_dt = datetime.combine(meet_date.date(), meet_time)
            meet_duration = int(row["duration"]) * 60

            meetings.append({
                "id": row["id"],
                "pw": row["password"],
                "duration": meet_duration,
                "desc": row["description"],
                "datetime": start_dt,
                "date": meet_date,
            })
    return meetings


def schedule_new_meetings(meetings):
    """Schedule only new meetings — skip ones already loaded."""
    for m in meetings:
        meeting_key = f"{m['id']}|{m['datetime'].isoformat()}"
        if meeting_key in scheduled_meetings:
            continue  # already scheduled

        run_time = (m["datetime"] - timedelta(minutes=5)).strftime("%H:%M")
        job = partial(
            join_if_correct_date,
            m["id"],
            m["pw"],
            m["duration"],
            m["desc"],
            m["date"]
        )
        schedule.every().day.at(run_time).do(job)
        scheduled_meetings.add(meeting_key)

        logging.info(f"📅 Scheduled: {m['desc']} at {run_time} for {m['datetime']}")


def refresh_schedule():
    """Reload CSV periodically and schedule newly added meetings."""
    global csv_last_load

    now = time.time()
    if csv_last_load and now - csv_last_load < CSV_RELOAD_SECONDS:
        return  # not time to reload yet

    logging.info("🔄 Reloading meetings CSV...")
    csv_last_load = now

    meetings = load_meetings_from_csv()
    schedule_new_meetings(meetings)

    # Catch-up logic only runs *once per meeting key*
    now_dt = datetime.now()
    for m in meetings:
        meeting_key = f"{m['id']}|{m['datetime'].isoformat()}"
        if meeting_key not in scheduled_meetings:  # newly found meeting
            start = m["datetime"]
            end = start + timedelta(seconds=m["duration"] + 600)
            if start <= now_dt <= end:
                logging.info(f"⚡ Catch-up join: {m['desc']}")
                join(m["id"], m["pw"], m["duration"], m["desc"])


# ---------------- Main -----------------
def main():
    try:
        if DEBUG and not os.path.exists(DEBUG_PATH):
            os.makedirs(DEBUG_PATH)
    except Exception:
        logging.error("Failed to create screenshot folder!")
        raise
    logging.info("✅ Zoom Recorder Started")
    refresh_schedule()  # initial load

if __name__ == '__main__':
    main()
    

while True:
    refresh_schedule()
    schedule.run_pending()
    time.sleep(1)
