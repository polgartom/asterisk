import os
from requests_tor import RequestsTor
import json
import time
import logging
import signal
import time
import argparse
import mysql.connector

mydb = mysql.connector.connect(
  host="127.0.0.1",
  user="polgar",
  password="123",
  database="iis",
  auth_plugin='mysql_native_password'
)

F_ID = 0
F_FPATH = 3
F_EXT = 4
F_SIZE_BYTES = 5
F_RECV_BYTES = 6
F_RESP_CODE = 7
F_TOR_PORT = 8
F_DONE = 10
F_TAKE_MS = 11

parser = argparse.ArgumentParser()
parser.add_argument('port', action='store', type=int)
parser.add_argument('--resp-code', type=int, default=0, required=False)
parser.add_argument('--exclude-ext', required=False) # ',' separator
parser.add_argument('--query-all-tor-port', type=int, default=0, required=False)
args = parser.parse_args()

if args.exclude_ext != None:
	args.exclude_ext = args.exclude_ext.split(',')

# logging.basicConfig(filename='d2.log', encoding='utf-8', level=logging.DEBUG)

# SELECT count(id) FROM `files` where resp_code = 500;
# SELECT count(id), resp_code FROM `files` GROUP by resp_code;

ONION_URL = "http://rhysidaqho36b6i6mvpmy5di4ro5zglovtxixrirky6q3fgack7q5uyd.onion/tbFV5Z1UNwqKQCJd9JmdtqrSGeWMLHoa"
timeouts = 0

# def siginthandler(signum, frame):
#     print("Interrupted! SIGINT")
#     exit(1)
# signal.signal(signal.SIGINT, siginthandler)

def sql_quote_and_concat_items(items):
	fmt = ','.join(['"%s"'] * len(items))
	return fmt % tuple(items)

def get_next_file_row():
	global mydb, args

	sql = "select * from files where true"

	if args.exclude_ext:
		exts = sql_quote_and_concat_items(args.exclude_ext)
		sql += " and ext not in ({})".format(exts) 

	if args.query_all_tor_port == 0:
		sql += " and tor_port={}".format(args.port)

	if args.resp_code != 0:
		sql += " and resp_code = {}".format(args.resp_code)
	else:
		sql += " and resp_code is null".format(args.port)

	sql += " limit 1"

	mycursor = mydb.cursor()
	mycursor.execute(sql)
	rows = mycursor.fetchall()
	if len(rows) == 0:
		return False
	return rows[0]

def get_filesize(fpath):
	with open(fpath, 'rb') as f:
		data = f.read()
		f.close()
		return len(data)

def update_file_row(_id, resp_code, recv_bytes, take_times_ms):
	sql = "update files set done=%s, resp_code=%s, recv_bytes=%s, take_times_ms=%s  where id=%s"
	val = (1, resp_code, recv_bytes, take_times_ms, _id)
	mycursor = mydb.cursor()
	mycursor.execute(sql, val)
	mydb.commit()
	# cc = mycursor.rowcount
	print("\tupdated in db.\n".format(_id))
	return True

def writefile(fpath, data):
	os.makedirs(os.path.dirname(fpath), exist_ok=True)
	with open(fpath, "wb") as f:
		f.write(data)
		f.close()

def download():
	global dirs, log, timeouts

	rt = RequestsTor(tor_ports=(args.port,), tor_cport=9051, password='XMASS__ASIX//99', autochange_id=20)
	rt.check_ip()

	while True:
		row = get_next_file_row()
		if row == False: break;
		fpath = "data/{}".format(row[F_FPATH])

		print("#{} ".format(row[F_ID]), end="")
		print(fpath, end="\n")
		url = "{}/{}".format(ONION_URL, fpath)
		if os.path.isfile(fpath):
			saved_size = os.stat(fpath).st_size
			print("\thaveit!")
			update_file_row(row[F_ID], 200, saved_size, 0)
			continue

		start = time.time()

		try:
			r = rt.get(url, timeout=8)
			content = r.content
		except Exception as e:
			print(e)
			print("!!! TIMEOUT EXCEPTION !!!\n")
			return False

		if r.ok == False:
			if r.status_code != args.resp_code:
				# mark this file as not accessible (temporary)
				update_file_row(row[F_ID], r.status_code, 0, 0)
				print("\tRESP NOT OK, SKIPPED r.status_code: {}\n".format(r.status_code))
			else:
				print("\ttry again!\n");
			continue

		writefile(fpath, r.content)

		end = time.time() - start
		take_ms = round(end*1000, 0)
		recv_size = len(content)
		update_file_row(row[F_ID], r.status_code, recv_size, take_ms)

		print("\t{} ms -- {} bytes -- OK\n".format(take_ms, recv_size))

	return True

loops = 0
done = False
while done != True:
	time.sleep(1)
	print("NEW LOOP -> #{}".format(loops))
	loops += 1
	done = download()

print("!!! DONE ; loops: {} !!!".format(loops))

exit(0)