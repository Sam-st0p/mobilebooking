<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Booking extends Model
{
    use HasFactory;

    protected $table = 'bookings';
    protected $keyType = 'string';
    public $incrementing = false; // Supabase uses UUIDs
    protected $guarded = [];
}
