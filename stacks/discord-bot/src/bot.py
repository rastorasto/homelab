import discord
from discord.ext import commands
from discord.ext import tasks
import subprocess
import os
import json
import sys
import aiohttp
import subprocess
import aiofiles
import asyncio
import time
import datetime
import asyncio
import requests
from deluge_client import DelugeRPCClient
import base64
from dotenv import load_dotenv




CHANNEL_ID = 1317572961762410522

load_dotenv()

TOKEN = os.getenv("DISCORD_TOKEN")
if not TOKEN:
    raise ValueError("Missing DISCORD_TOKEN in .env")

intents = discord.Intents.default()
intents.message_content = True
bot = commands.Bot(command_prefix="!", intents=intents)
last_video_id = None  # global to track last video


@bot.command()
@commands.has_permissions(manage_messages=True)  # Optional: restrict to mods/admins
async def clear(ctx, amount: int = 100):
    """Clears messages in the current channel. Default is 100 messages."""
    deleted = await ctx.channel.purge(limit=amount)
    await ctx.send(f"🧹 Cleared {len(deleted)} messages.", delete_after=5)


@bot.command()
async def ping(ctx):
    await ctx.send("Pong!")

@bot.command()
async def bf(ctx):
    await ctx.send(":rabbit:   :heart:   𝑀𝒾𝓀𝑒𝓎  :heart:    :rabbit2: ")

@bot.command()
@commands.has_permissions(manage_messages=True)
async def restart(ctx):
    await ctx.send("🔄 Restarting bot...")

    await bot.close()

    os.execv(sys.executable, [sys.executable] + sys.argv)

@bot.event
async def on_ready():
    print(f"Bot is online as {bot.user}")


    channel = bot.get_channel(CHANNEL_ID)
    if channel:
        await channel.send("🤖 *beep boop* I'M ALIVE! Did you miss me meow?")

@bot.command()
async def cat(ctx):
    async with aiohttp.ClientSession() as session:
        async with session.get("https://api.thecatapi.com/v1/images/search") as resp:
            if resp.status != 200:
                await ctx.send("Couldn't fetch a cat right now 😿")
                return
            data = await resp.json()
            await ctx.send(data[0]["url"])

@bot.command()
@commands.has_permissions(manage_messages=True)
async def command(ctx, *, cmd: str):

    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
        output = result.stdout.strip() or result.stderr.strip() or "✅ Command ran with no output."

        if len(output) > 1900:
            output = output[:1900] + "\n... (truncated)"

        await ctx.send(f"```bash\n{output}\n```")
    except Exception as e:
        await ctx.send(f"❌ Error: {e}")

bot.run(TOKEN)
