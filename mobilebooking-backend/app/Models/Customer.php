<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Customer extends Model
{
    use HasFactory;

    protected $table = 'customers';
    protected $keyType = 'string';
    public $incrementing = false; // Supabase uses UUIDs
    protected $guarded = [];
}
